module Blizzard
  module Api
    module GameData
      module PvpSeason
        class SeasonsIndex < Blizzard::Api::BaseRequest
          def self.fetch(region: "us", locale: "en_US", params: {})
            client = client(region:, locale:)

            client.get("/data/wow/pvp-season/index",
                       namespace: client.dynamic_namespace,
                       params:    params)
          end
        end
      end
    end
  end
end
