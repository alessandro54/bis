module Pvp
  class SyncCharacterBatchJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :character_sync

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

      # Collect all entry IDs that need processing
      all_entry_ids = []

      # Process sequentially - parallelism is achieved via multiple batch jobs
      # Threading within a job causes connection pool exhaustion
      characters_by_id.each_value do |character|
        entry_ids = sync_one(character: character, locale: locale)
        all_entry_ids.concat(entry_ids) if entry_ids.present?
      end

      # Enqueue a single batch job for all entries instead of one per character
      if all_entry_ids.any?
        Pvp::ProcessLeaderboardEntryBatchJob.perform_later(
          entry_ids: all_entry_ids,
          locale:    locale
        )
      end
    end

    private

      # Returns array of entry IDs that need processing, or nil
      def sync_one(character:, locale:)
        return unless character

        result = Pvp::Characters::SyncCharacterService.call(
          character:          character,
          locale:             locale,
          enqueue_processing: false  # Don't enqueue individually, we'll batch them
        )

        return unless result.success?

        # Return entry IDs if fresh snapshot was applied
        result.context[:entry_ids_to_process]
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
