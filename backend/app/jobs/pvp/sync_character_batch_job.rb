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

      # Process with controlled concurrency for API calls
      all_entry_ids = process_characters_concurrently(characters_by_id.values, locale)

      # Enqueue a single batch job for all entries instead of one per character
      return unless all_entry_ids.any?

      Pvp::ProcessLeaderboardEntryBatchJob.perform_later(
        entry_ids: all_entry_ids,
        locale:    locale
      )
    end

    private

      def process_characters_concurrently(characters, locale)
        return [] if characters.empty?

        concurrency = [ CONCURRENCY, characters.size ].min
        all_entry_ids = Concurrent::Array.new

        # Use a thread pool for concurrent API calls
        pool = Concurrent::FixedThreadPool.new(concurrency)

        characters.each do |character|
          pool.post do
            entry_ids = sync_one(character: character, locale: locale)
            all_entry_ids.concat(entry_ids) if entry_ids.present?
          end
        end

        pool.shutdown
        pool.wait_for_termination

        all_entry_ids.to_a
      end

      # Returns array of entry IDs that need processing, or nil
      def sync_one(character:, locale:)
        return unless character

        # Each thread gets its own DB connection
        ActiveRecord::Base.connection_pool.with_connection do
          result = Pvp::Characters::SyncCharacterService.call(
            character:          character,
            locale:             locale,
            enqueue_processing: false # Don't enqueue individually, we'll batch them
          )

          return unless result.success?

          # Return entry IDs if fresh snapshot was applied
          result.context[:entry_ids_to_process]
        end
      rescue Blizzard::Client::Error => e
        # Log but don't raise - let other characters in batch continue processing
        Rails.logger.warn(
          "[SyncCharacterBatchJob] API error for character #{character&.id}: #{e.message}"
        )
        nil
      rescue => e
        Rails.logger.error(
          "[SyncCharacterBatchJob] Unexpected error for character #{character&.id}: #{e.class}: #{e.message}"
        )
        nil
      end
  end
end
