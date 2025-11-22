module Blizzard
  module Api
    module Profile
      class CharacterEquipmentSummary < Blizzard::Api::BaseRequest
        def self.fetch(region:, name:, realm:, locale: "en_US", params: {})
          client = client(region:, locale:)

          realm_slug = CGI.escape(realm.downcase)
          name_slug = CGI.escape(name.downcase)

          client.get("/profile/wow/character/#{realm_slug}/#{name_slug}/equipment",
                     namespace: client.profile_namespace,
                     params: params)
        end
      end
    end
  end
end
