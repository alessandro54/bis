# Optimized batch job with true bulk operations and intelligent batching
module Pvp
  class OptimizedSyncCharacterBatchJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :character_sync
    priority 10 # High priority for time-sensitive operations

    def perform(character_ids:, locale: "en_US", processing_queues: nil)
      ids = Array(character_ids).compact
      return if ids.empty?

      process_character_batches(ids, locale, processing_queues)
    end

    private

      def process_character_batches(ids, locale, processing_queues)
        batch_size = calculate_optimal_batch_size
        batches = ids.each_slice(batch_size)
        parallel_batches = ENV.fetch("CHARACTER_BATCH_PARALLELISM", 5).to_i

        if parallel_batches == 1
          process_batches_sequentially(batches, locale, processing_queues)
        else
          process_batches_concurrently(batches, locale, processing_queues, parallel_batches)
        end
      end

      def process_batches_sequentially(batches, locale, processing_queues)
        batches.each { |batch| process_batch(batch, locale, processing_queues) }
      end

      def process_batches_concurrently(batches, locale, processing_queues, parallel_batches)
        require "concurrent-ruby"
        pool = Concurrent::ThreadPoolExecutor.new(
          min_threads: 1,
          max_threads: parallel_batches,
          max_queue:   parallel_batches * 2
        )

        futures = batches.map do |batch|
          Concurrent::Future.execute(executor: pool) do
            process_batch(batch, locale, processing_queues)
          end
        end

        futures.each(&:value!)
        pool.shutdown
        pool.wait_for_termination(30)
      end

    private

      def calculate_optimal_batch_size
        # Dynamic batch sizing based on system load and API limits
        base_size = ENV.fetch("CHARACTER_BATCH_SIZE", 25).to_i

        # Adjust based on current load (simple heuristic)
        load_average = get_system_load
        if load_average > 2.0
          [ base_size / 2, 5 ].max
        elsif load_average < 0.5
          [ base_size * 2, 50 ].min
        else
          base_size
        end
      end

      def get_system_load
        # Simple load detection - in production you might use more sophisticated metrics
        begin
          `uptime`.match(/load averages?: ([\d.]+)/)[1].to_f
        rescue
          1.0 # Default if we can't determine load
        end
      end

      def process_batch(character_ids, locale, processing_queues)
        characters = preload_characters(character_ids)
        results = process_characters_with_service(character_ids, characters, locale, processing_queues)
        log_batch_statistics(results, character_ids.size)
        schedule_retry_for_failed_jobs(character_ids, results, locale, processing_queues)
      end

      def preload_characters(character_ids)
        Character.where(id: character_ids)
                 .includes(:pvp_leaderboard_entries)
                 .index_by(&:id)
      end

      def process_characters_with_service(character_ids, characters, locale, processing_queues)
        character_ids.map do |character_id|
          character = characters[character_id]
          next unless character

          Pvp::Characters::OptimizedSyncCharacterService.call(
            character:         character,
            locale:            locale,
            processing_queues: processing_queues
          )
        end.compact
      end

      def log_batch_statistics(results, total_count)
        successful = results.count(&:success?)
        failed = results.count(&:failure?)

        Rails.logger.info(
          "[OptimizedSyncCharacterBatchJob] Batch completed: " \
          "#{successful} successful, #{failed} failed out of #{total_count}"
        )
      end

      def schedule_retry_for_failed_jobs(character_ids, results, locale, processing_queues)
        failed_count = results.count(&:failure?)
        return unless failed_count > 0

        failed_ids = character_ids.select.with_index { |_, i| results[i]&.failure? }
        schedule_retry(failed_ids, locale, processing_queues)
      end

      def schedule_retry(failed_ids, locale, processing_queues)
        # Exponential backoff for retry
        delay = [ failed_ids.size * 30.seconds, 5.minutes ].min

        OptimizedSyncCharacterBatchJob
          .set(wait: delay, priority: 5)
          .perform_later(
            character_ids:     failed_ids,
            locale:            locale,
            processing_queues: processing_queues
          )
      end
  end
end
