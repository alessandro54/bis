# app/jobs/pvp/process_leaderboard_entry_job.rb
module Pvp
  class ProcessLeaderboardEntryJob < ApplicationJob
    queue_as :pvp_processing

    def perform(entry_id:, locale: "en_US")
      entry = ::PvpLeaderboardEntry.find_by(id: entry_id)
      return unless entry

      result = Pvp::Entries::ProcessEntryService.call(entry: entry, locale: locale)

      return if result.success?

      Rails.logger.error(
        "[ProcessLeaderboardEntryJob] Failed for entry #{entry_id}: #{result.error}"
      )
    end
  end
end
