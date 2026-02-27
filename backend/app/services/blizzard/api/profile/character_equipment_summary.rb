module Blizzard
  module Api
    module Profile
      class CharacterEquipmentSummary < Blizzard::Api::BaseRequest
        def self.fetch(region:, name:, realm:, locale: "en_US", params: {})
          client = client(region:, locale:)
          client.get(path(realm, name),
                     namespace: client.profile_namespace,
                     params:    params)
        end

        # Returns [body_or_nil, last_modified, changed] — see Client#get_with_last_modified.
        def self.fetch_with_last_modified(region:, name:, realm:, locale: "en_US", last_modified: nil, params: {})
          client = client(region:, locale:)
          client.get_with_last_modified(path(realm, name),
                                        namespace:     client.profile_namespace,
                                        params:        params,
                                        last_modified: last_modified)
        end

        def self.path(realm, name)
          "/profile/wow/character/#{CGI.escape(realm.downcase)}/#{CGI.escape(name.downcase)}/equipment"
        end
        private_class_method :path
      end
    end
  end
end
