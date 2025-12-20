module Pvp
  class ProcessLeaderboardEntryBatchJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :pvp_processing

    def perform(entry_ids:, locale: "en_US")
      ids = Array(entry_ids).compact
      return if ids.empty?

      parallelism = ENV.fetch("PVP_PROCESSING_BATCH_PARALLELISM", 2).to_i
      parallelism = 1 if parallelism < 1

      if parallelism == 1
        ids.each { |entry_id| process_one(entry_id: entry_id, locale: locale) }
        return
      end

      work_queue = ::Queue.new
      ids.each { |id| work_queue << id }

      threads = Array.new(parallelism) do
        Thread.new do
          while (entry_id = (work_queue.pop(true) rescue nil))
            process_one(entry_id: entry_id, locale: locale)
          end
        end
      end

      threads.each(&:join)
    end

    private

      def process_one(entry_id:, locale:)
        entry = ::PvpLeaderboardEntry.find_by(id: entry_id)
        return unless entry

        result = Pvp::Entries::ProcessEntryService.call(entry: entry, locale: locale)
        return if result.success?

        Rails.logger.error(
          "[ProcessLeaderboardEntryBatchJob] Failed for entry #{entry_id}: #{result.error}"
        )
      rescue => e
        Rails.logger.error(
          "[ProcessLeaderboardEntryBatchJob] Error for entry #{entry_id}: #{e.class}: #{e.message}"
        )
      end
  end
end
