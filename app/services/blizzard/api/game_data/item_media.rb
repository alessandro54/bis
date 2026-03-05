module Blizzard
  module Api
    module GameData
      class ItemMedia < Blizzard::Api::BaseRequest
        def self.fetch(blizzard_id:, region: "us")
          client = client(region: region)
          client.get("/data/wow/media/item/#{blizzard_id}",
                     namespace: client.static_namespace)
        end
      end
    end
  end
end
