# app/services/blizzard/api/profile/base_request.rb
module Blizzard
  module Api
    module Profile
      class BaseRequest
        attr_reader :client

        def initialize(region:, locale: "en_US")
          @client = Blizzard::Client.new(region:, locale:)
        end
      end
    end
  end
end
