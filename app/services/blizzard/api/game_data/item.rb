module Blizzard
  module Api
    module GameData
      class Item < Blizzard::Api::BaseRequest
        def self.fetch(blizzard_id:, region: "us", locale: "en_US")
          client = client(region: region, locale: locale)
          client.get("/data/wow/item/#{blizzard_id}", namespace: client.static_namespace)
        end
      end
    end
  end
end
