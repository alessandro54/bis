require "net/http"
require "uri"
require "json"

module Blizzard
  class Auth
    class Error < StandardError; end

    OAUTH_URL = "https://oauth.battle.net/oauth/token".freeze
    CACHE_KEY = "blizzard_access_token".freeze
    EXPIRY_SKEW_SECONDS = 60

    def initialize(
      client_id: Rails.application.credentials.dig(:blizzard, :client_id),
      client_secret: Rails.application.credentials.dig(:blizzard, :client_secret)
    )
      @client_id = client_id
      @client_secret = client_secret

      return unless @client_id.blank? || @client_secret.blank?

      raise ArgumentError, "Blizzard client_id and client_secret must be provided"
    end

    def access_token
      cached = Rails.cache.read(CACHE_KEY)

      if cached.present? &&
         cached[:token].present? &&
         cached[:expires_at].present? &&
         cached[:expires_at] > Time.current
        return cached[:token]
      end

      fetch_and_cache_access_token!
    end

    private

      def fetch_and_cache_access_token!
        response = perform_oauth_request
        body     = parse_response_body(response)
        token, expires_in = extract_token_data(body)

        expires_at = compute_expires_at(expires_in)

        write_cache(token, expires_at, expires_in)

        token
      end

      def perform_oauth_request
        uri = URI.parse(OAUTH_URL)

        request = Net::HTTP::Post.new(uri)
        request.basic_auth(@client_id, @client_secret)
        request.set_form_data(grant_type: "client_credentials")

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        return response if response.is_a?(Net::HTTPSuccess)

        raise Error, "Blizzard OAuth error: HTTP #{response.code} #{response.message}"
      end

      def parse_response_body(response)
        JSON.parse(response.body)
      rescue JSON::ParserError
        raise Error, "Blizzard OAuth error: invalid JSON response\n#{response.body}"
      end

      def extract_token_data(body)
        token      = body["access_token"]
        expires_in = body["expires_in"].to_i

        if token.blank? || expires_in.zero?
          raise Error, "Blizzard OAuth error: response does not include access_token.\n#{body.inspect}"
        end

        [ token, expires_in ]
      end

      def compute_expires_at(expires_in)
        Time.current + expires_in - EXPIRY_SKEW_SECONDS
      end

      def write_cache(token, expires_at, expires_in)
        Rails.cache.write(
          CACHE_KEY,
          { token: token, expires_at: expires_at },
          expires_in: expires_in
        )
      end
  end
end
