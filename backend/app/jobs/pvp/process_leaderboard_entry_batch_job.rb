module Pvp
  class ProcessLeaderboardEntryBatchJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :pvp_processing

    # Concurrency for parallel processing - lower default for resource-constrained servers
    CONCURRENCY = ENV.fetch("PVP_PROCESSING_CONCURRENCY", 4).to_i

    # rubocop:disable Metrics/AbcSize
    def perform(entry_ids:, locale: "en_US")
      ids = Array(entry_ids).compact
      return if ids.empty?

      # Filter out already processed entries at batch level to avoid redundant work
      # Same entry may be queued multiple times from different character syncs
      ttl_hours = ENV.fetch("EQUIPMENT_PROCESS_TTL_HOURS", 1).to_i
      cutoff = ttl_hours.hours.ago

      # Preload entries with characters (avoid N+1) and filter unprocessed
      entries = ::PvpLeaderboardEntry
        .includes(:character)
        .where(id: ids)
        .where("equipment_processed_at IS NULL OR equipment_processed_at < ?", cutoff)
        .to_a

      return if entries.empty?

      # Log skip count for monitoring
      skipped = ids.size - entries.size
      if skipped > 0
        Rails.logger.info(
          "[ProcessLeaderboardEntryBatchJob] Skipped #{skipped}/#{ids.size} already processed entries"
        )
      end

      # Process entries with controlled concurrency
      process_entries_concurrently(entries, locale)
    end
    # rubocop:enable Metrics/AbcSize

    private

      def process_entries_concurrently(entries, locale)
        return if entries.empty?

        concurrency = safe_concurrency(CONCURRENCY, entries.size)

        # Use thread pool for parallel processing
        pool = Concurrent::FixedThreadPool.new(concurrency)

        entries.each do |entry|
          pool.post do
            process_one(entry: entry, locale: locale)
          end
        end

        pool.shutdown
        pool.wait_for_termination
      end

      def process_one(entry:, locale:)
        return unless entry

        # Each thread gets its own DB connection
        ActiveRecord::Base.connection_pool.with_connection do
          result = Pvp::Entries::ProcessEntryService.call(entry: entry, locale: locale)
          return if result.success?

          Rails.logger.error(
            "[ProcessLeaderboardEntryBatchJob] Failed for entry #{entry.id}: #{result.error}"
          )
        end
      rescue => e
        Rails.logger.error(
          "[ProcessLeaderboardEntryBatchJob] Error for entry #{entry&.id}: #{e.class}: #{e.message}"
        )
      end
  end
end
