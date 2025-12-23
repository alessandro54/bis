# Optimized batch processing with true bulk operations and intelligent resource management
module Pvp
  class OptimizedProcessLeaderboardEntryBatchJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :pvp_processing
    priority 5 # Medium priority

    def perform(entry_ids:, locale: "en_US")
      ids = Array(entry_ids).compact
      return if ids.empty?

      process_leaderboard_batches(ids, locale)
    end

    private

      def process_leaderboard_batches(ids, locale)
        batch_size = calculate_optimal_batch_size
        batches = ids.each_slice(batch_size)
        parallel_batches = ENV.fetch("PVP_BATCH_PARALLELISM", 8).to_i

        if parallel_batches == 1
          process_batches_sequentially(batches, locale)
        else
          process_batches_concurrently(batches, locale, parallel_batches)
        end
      end

      def process_batches_sequentially(batches, locale)
        batches.each { |batch| process_batch(batch, locale) }
      end

      def process_batches_concurrently(batches, locale, parallel_batches)
        require "concurrent-ruby"
        pool = Concurrent::ThreadPoolExecutor.new(
          min_threads: 2,
          max_threads: parallel_batches,
          max_queue:   parallel_batches * 3
        )

        futures = batches.map do |batch|
          Concurrent::Future.execute(executor: pool) do
            process_batch(batch, locale)
          end
        end

        futures.each(&:value!)
        pool.shutdown
        pool.wait_for_termination(60)
      end

    private

      def calculate_optimal_batch_size
        # Dynamic batch sizing based on available memory and database performance
        base_size = ENV.fetch("PVP_BATCH_SIZE", 50).to_i

        # Monitor database connection usage
        available_connections = get_available_db_connections

        if available_connections < 10
          [ base_size / 2, 10 ].max
        elsif available_connections > 30
          [ base_size * 2, 100 ].min
        else
          base_size
        end
      end

      def get_available_db_connections
        # Simple connection monitoring - in production use proper metrics
        begin
          ActiveRecord::Base.connection_pool.stat[:available]
        rescue
          20 # Default if we can't determine
        end
      end

      def process_batch(entry_ids, locale)
        # Bulk preload to eliminate N+1 queries
        entries = PvpLeaderboardEntry
          .where(id: entry_ids)
          .includes(:character, :pvp_leaderboard)
          .index_by(&:id)

        # Separate entries by processing needs for optimized batching
        equipment_entries = []
        specialization_entries = []

        entry_ids.each do |entry_id|
          entry = entries[entry_id]
          next unless entry

          equipment_entries << entry if needs_equipment_processing?(entry)
          specialization_entries << entry if needs_specialization_processing?(entry)
        end

        # Process equipment in bulk
        process_equipment_bulk(equipment_entries, locale) unless equipment_entries.empty?

        # Process specializations in bulk
        process_specialization_bulk(specialization_entries) unless specialization_entries.empty?

        # Log batch statistics
        Rails.logger.info(
          "[OptimizedProcessLeaderboardEntryBatchJob] Batch processed: " \
          "#{equipment_entries.size} equipment, #{specialization_entries.size} specialization"
        )
      end

      def needs_equipment_processing?(entry)
        entry.equipment_processed_at.nil? || entry.equipment_processed_at < 1.hour.ago
      end

      def needs_specialization_processing?(entry)
        entry.specialization_processed_at.nil? || entry.specialization_processed_at < 1.hour.ago
      end

      def process_equipment_bulk(entries, locale)
        # Group by character to optimize API calls
        entries_by_character = entries.group_by(&:character_id)

        entries_by_character.each do |character_id, character_entries|
          character = character_entries.first.character

          # Fetch equipment data once per character
          equipment_data = fetch_character_equipment(character, locale)
          next unless equipment_data

          # Process all entries for this character
          character_entries.each do |entry|
            process_single_equipment(entry, equipment_data)
          end
        end
      end

      def process_specialization_bulk(entries)
        # Group by character to optimize API calls
        entries_by_character = entries.group_by(&:character_id)

        entries_by_character.each do |character_id, character_entries|
          character = character_entries.first.character

          # Fetch specialization data once per character
          spec_data = fetch_character_specialization(character)
          next unless spec_data

          # Process all entries for this character
          character_entries.each do |entry|
            process_single_specialization(entry, spec_data)
          end
        end
      end

      def fetch_character_equipment(character, locale)
        # Use cached client for better performance
        client = Blizzard::Client.new(locale: locale, use_cache: true)
        client.character_equipment(character)
      rescue => e
        Rails.logger.warn("Failed to fetch equipment for character #{character.id}: #{e.message}")
        nil
      end

      def fetch_character_specialization(character)
        client = Blizzard::Client.new(use_cache: true)
        client.character_specializations(character)
      rescue => e
        Rails.logger.warn("Failed to fetch specializations for character #{character.id}: #{e.message}")
        nil
      end

      def process_single_equipment(entry, equipment_data)
        result = Pvp::Entries::ProcessEquipmentService.call(
          entry:  entry,
          locale: locale
        )

        return if result.success?

        Rails.logger.warn("Equipment processing failed for entry #{entry.id}: #{result.error}")
      end

      def process_single_specialization(entry, spec_data)
        result = Pvp::Entries::ProcessSpecializationService.call(entry: entry)

        return if result.success?

        Rails.logger.warn("Specialization processing failed for entry #{entry.id}: #{result.error}")
      end
  end
end
