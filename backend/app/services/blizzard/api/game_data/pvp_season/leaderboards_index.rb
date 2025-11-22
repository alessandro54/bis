module Blizzard
  module Api
    module GameData
      module PvpSeason
        class LeaderboardsIndex < Blizzard::Api::BaseRequest
          def self.fetch(pvp_season_id:, region: "us", locale: "en_US", params: {})
            client = client(region:, locale:)

            client.get("/data/wow/pvp-season/#{pvp_season_id}/pvp-leaderboard/index",
                       namespace: client.dynamic_namespace,
                       params: params)
          end
        end
      end
    end
  end
end
