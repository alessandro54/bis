class SyncCurrentPvpSeasonLeaderboardsJob < ApplicationJob
  queue_as :default

  def perform(region: "us", locale: "en_US")
    season = PvpSeason.find_by(blizzard_id: 40)

    return unless season

    %w[3v3].each do |bracket|
      SyncPvpLeaderboardJob.perform_later(
        region:,
        season:,
        bracket:,
        locale:
      )
    end
  end
end
