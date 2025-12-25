module Pvp
  class SyncCurrentSeasonLeaderboardsJob < ApplicationJob
    queue_as :default

    BRACKETS = %w[ 2v2 3v3 rbg shuffle-overall ].freeze

    def perform(region: "us", locale: "en_US")
      season = PvpSeason.current
      return unless season

      BRACKETS.each do |bracket|
        bracket_config = Pvp::BracketConfig.for(bracket)
        queue = bracket_config&.dig(:job_queue) || :default

        SyncLeaderboardJob
          .set(queue: queue)
          .perform_later(
            region:  region,
            season:  season,
            bracket: bracket,
            locale:  locale
          )
      end
    end
  end
end
