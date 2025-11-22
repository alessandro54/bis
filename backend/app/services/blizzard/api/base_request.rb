# app/services/blizzard/api/profile/base_request.rb
module Blizzard
  module Api
    class BaseRequest
      attr_reader :client

      def initialize(region:, locale: "en_US")
        @client = Blizzard.client(region:, locale:)
      end

      def self.client(region:, locale: "en_US")
        new(region:, locale:).client
      end
    end
  end
end
