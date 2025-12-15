# app/jobs/pvp/process_leaderboard_entry_job.rb
module Pvp
  class ProcessLeaderboardEntryJob < ApplicationJob
    PROCESSING_QUEUES = %i[
      pvp_processing_a
      pvp_processing_b
      pvp_processing_c
      pvp_processing_d
    ].freeze

    queue_as :pvp_processing

    def perform(entry_id:, locale: "en_US")
      entry = ::PvpLeaderboardEntry.find_by(id: entry_id)
      return unless entry

      result = Pvp::Entries::ProcessEntryService.call(entry: entry, locale: locale)

      return if result.success?

      error_message = "[ProcessLeaderboardEntryJob] Failed for entry #{entry_id}: #{result.error}"
      Rails.logger.error(error_message)

      raise(result.error) if result.error.is_a?(Exception)
      raise(StandardError, error_message)
    end

    def self.queue_for(entry_id, queues: nil)
      queues ||= PROCESSING_QUEUES
      queues[entry_id % queues.size]
    end
  end
end
