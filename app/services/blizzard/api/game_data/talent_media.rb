module Blizzard
  module Api
    module GameData
      class TalentMedia < Blizzard::Api::BaseRequest
        def self.fetch(blizzard_id:, region: "us")
          client = client(region: region)
          client.get("/data/wow/media/talent/#{blizzard_id}", namespace: client.static_namespace)
        end
      end
    end
  end
end
