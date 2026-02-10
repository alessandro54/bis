module Pvp
  class SyncCharacterBatchJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :character_sync

    # Number of concurrent API calls per batch job
    # Blizzard API allows 100 requests/second, but lower defaults for resource-constrained servers
    # Increase via environment variable for more powerful instances
    CONCURRENCY = ENV.fetch("PVP_SYNC_CONCURRENCY", 5).to_i

    # Retry on API errors with exponential backoff
    retry_on Blizzard::Client::Error, wait: :polynomially_longer, attempts: 3 do |_job, error|
      Rails.logger.warn("[SyncCharacterBatchJob] API error, will retry: #{error.message}")
    end

    def perform(character_ids:, locale: "en_US")
      ids = Array(character_ids).compact
      return if ids.empty?

      # Preload all non-private characters in one query
      # Filter out private characters early to avoid unnecessary processing
      characters_by_id = Character
        .where(id: ids)
        .where(is_private: false)
        .index_by(&:id)

      return if characters_by_id.empty?

      outcome = BatchOutcome.new

      # Process with controlled concurrency for API calls
      all_entry_ids = process_characters_concurrently(characters_by_id.values, locale, outcome)

      Rails.logger.info(outcome.summary_message(job_label: "SyncCharacterBatchJob"))
      outcome.raise_if_total_failure!(job_label: "SyncCharacterBatchJob")

      # Enqueue a single batch job for all entries instead of one per character
      return unless all_entry_ids.any?

      Pvp::ProcessLeaderboardEntryBatchJob.perform_later(
        entry_ids: all_entry_ids,
        locale:    locale
      )
    end

    private

      def process_characters_concurrently(characters, locale, outcome)
        return [] if characters.empty?

        concurrency = safe_concurrency(CONCURRENCY, characters.size)

        results = run_concurrently(characters, concurrency: concurrency) do |character|
          sync_one(character: character, locale: locale, outcome: outcome)
        end

        results.flatten
      end

      # Returns array of entry IDs that need processing, or nil
      def sync_one(character:, locale:, outcome:)
        return unless character

        # Each fiber gets its own DB connection
        ActiveRecord::Base.connection_pool.with_connection do
          result = Pvp::Characters::SyncCharacterService.call(
            character:          character,
            locale:             locale,
            enqueue_processing: false # Don't enqueue individually, we'll batch them
          )

          if result.success?
            outcome.record_success(id: character.id, status: result.context[:status])
            result.context[:entry_ids_to_process]
          else
            outcome.record_failure(id: character.id, status: :failed, error: result.error.to_s)
            nil
          end
        end
      rescue Blizzard::Client::RateLimitedError => e
        Rails.logger.warn(
          "[SyncCharacterBatchJob] Rate limited for character #{character&.id}: #{e.message}"
        )
        outcome.record_failure(id: character&.id, status: :rate_limited, error: e.message)
        nil
      rescue Blizzard::Client::Error => e
        # Log but don't raise - let other characters in batch continue processing
        Rails.logger.warn(
          "[SyncCharacterBatchJob] API error for character #{character&.id}: #{e.message}"
        )
        outcome.record_failure(id: character&.id, status: :api_error, error: e.message)
        nil
      rescue => e
        Rails.logger.error(
          "[SyncCharacterBatchJob] Unexpected error for character #{character&.id}: #{e.class}: #{e.message}"
        )
        outcome.record_failure(id: character&.id, status: :unexpected_error, error: "#{e.class}: #{e.message}")
        nil
      end
  end
end
