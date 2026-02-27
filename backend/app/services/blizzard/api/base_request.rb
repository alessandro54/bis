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

      # Blizzard profile URLs require the "slug" form of names:
      # lowercase + diacritics stripped to their ASCII base.
      # e.g. "Chodäboi" → "chodaboi", NOT "choд%C3%A4boi"
      def self.to_slug(str)
        str.downcase
           .unicode_normalize(:nfd)   # decompose: ä → a + combining diaeresis
           .gsub(/\p{Mn}/, "")        # strip all combining (accent) marks
      end
    end
  end
end
