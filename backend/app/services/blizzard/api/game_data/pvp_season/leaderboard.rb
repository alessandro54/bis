module Blizzard
  module Api
    module GameData
      module PvpSeason
        class Leaderboard < Blizzard::Api::BaseRequest
          def self.fetch(region:, pvp_season_id:, bracket:, locale: "en_US", params: {})
            client = client(region:, locale:)

            client.get("/data/wow/pvp-season/#{pvp_season_id}/pvp-leaderboard/#{bracket}",
                       namespace: client.dynamic_namespace,
                       params: params)
          end
        end
      end
    end
  end
end
