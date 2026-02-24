module Blizzard
  module Api
    module Profile
      class CharacterSpecializationSummary < Blizzard::Api::BaseRequest
        def self.fetch(region:, name:, realm:, locale: "en_US", params: {})
          client = client(region:, locale:)
          client.get(path(realm, name),
                     namespace: client.profile_namespace,
                     params:    params)
        end

        # Returns [body_or_nil, etag, changed] — see Client#get_with_etag.
        def self.fetch_with_etag(region:, name:, realm:, locale: "en_US", etag: nil, params: {})
          client = client(region:, locale:)
          client.get_with_etag(path(realm, name),
                               namespace: client.profile_namespace,
                               params:    params,
                               etag:      etag)
        end

        def self.path(realm, name)
          "/profile/wow/character/#{CGI.escape(realm.downcase)}/#{CGI.escape(name.downcase)}/specializations"
        end
        private_class_method :path
      end
    end
  end
end
