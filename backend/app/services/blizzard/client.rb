# app/services/blizzard/client.rb

module Blizzard
  class Client
    class Error < StandardError; end

    attr_reader :region, :locale, :auth

    API_HOST_TEMPLATE = "%{region}.api.blizzard.com".freeze

    VALID_REGIONS = %w[us eu kr tw].freeze

    VALID_LOCALES = {
      "us" => %w[en_US es_MX pt_BR],
      "eu" => %w[en_GB es_ES fr_FR de_DE it_IT ru_RU],
      "kr" => %w[ko_KR],
      "tw" => %w[zh_TW]
    }.stringify_keys!.freeze
    DEFAULT_LOCALE = "en_US".freeze

    def initialize(region: "us", locale: DEFAULT_LOCALE, auth: Blizzard::Auth.new)
      raise ArgumentError, "Unsupported Blizzard API region: #{region}" unless VALID_REGIONS.include?(region)

      allowed_locales = VALID_LOCALES.fetch(region)

      unless allowed_locales.include?(locale)
        raise ArgumentError, "Invalid locale '#{locale}' for region '#{region}'"
      end

      @region = region
      @locale = locale
      @auth = auth
    end

    def get(path, namespace:, params: {})
      url = build_url(path)

      query = {
        namespace: namespace,
        locale:    locale
      }.merge(params)

      headers = auth_header

      response = http_client.get(url, params: query, headers: headers)

      parse_response(response)
    end

    def profile_namespace = "profile-#{region}"
    def dynamic_namespace = "dynamic-#{region}"
    def static_namespace = "static-#{region}"

    private

      def http_client
        @http_client ||= HTTPX.with(
          timeout: {
            connect_timeout:   5,
            operation_timeout: 10
          }
          # debug: $stdout   # enable if needed
        )
      end

      def build_url(path)
        "https://#{API_HOST_TEMPLATE % { region: region }}#{path}"
      end

      def auth_header
        { Authorization: "Bearer #{auth.access_token}" }
      end

      def parse_response(response)
        return JSON.parse(response.body.to_s) if response.status == 200

        raise Error, "Blizzard API error: HTTP #{response.status}, body=#{response.body}"
      rescue JSON::ParserError => e
        raise Error, "Blizzard API error: invalid JSON: #{e.message}\n#{response.body}"
      end
  end
end
