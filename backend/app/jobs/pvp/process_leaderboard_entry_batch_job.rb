module Pvp
  class ProcessLeaderboardEntryBatchJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :pvp_processing

    def perform(entry_ids:, locale: "en_US")
      ids = Array(entry_ids).compact
      return if ids.empty?

      # Preload all entries in one query instead of N individual find_by calls
      entries_by_id = ::PvpLeaderboardEntry.where(id: ids).index_by(&:id)

      # Process sequentially - threading doesn't help for DB-bound work
      # and causes connection pool exhaustion issues
      ids.each do |id|
        process_one(entry: entries_by_id[id], locale: locale)
      end
    end

    private


      def process_one(entry:, locale:)
        return unless entry

        result = Pvp::Entries::ProcessEntryService.call(entry: entry, locale: locale)
        return if result.success?

        Rails.logger.error(
          "[ProcessLeaderboardEntryBatchJob] Failed for entry #{entry.id}: #{result.error}"
        )
      rescue => e
        Rails.logger.error(
          "[ProcessLeaderboardEntryBatchJob] Error for entry #{entry&.id}: #{e.class}: #{e.message}"
        )
      end
  end
end
