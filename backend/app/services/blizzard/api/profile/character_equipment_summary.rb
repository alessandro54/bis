module Blizzard
  module Api
    module Profile
      class CharacterEquipmentSummary < BaseRequest
        def self.fetch(region:, name:, realm:, locale: "en_US", params: {})
          new(region:, locale:).fetch(realm:, name:, params: params)
        end

        def fetch(realm:, name:, params: {})
          client.get("/profile/wow/character/#{realm}/#{name}/equipment",
                     namespace: client.profile_namespace,
                     params: params)
        end
      end
    end
  end
end
