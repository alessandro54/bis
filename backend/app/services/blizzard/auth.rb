require "httpx"
require "uri"
require "oj"

module Blizzard
  class Auth
    class Error < StandardError; end

    OAUTH_URL = "https://oauth.battle.net/oauth/token".freeze
    CACHE_KEY = "blizzard_access_token".freeze
    EXPIRY_SKEW_SECONDS = 60

    def initialize(
      client_id: Rails.application.credentials.dig(:blizzard, :client_id) || ENV["BLIZZARD_CLIENT_ID"],
      client_secret: Rails.application.credentials.dig(:blizzard, :client_secret) || ENV["BLIZZARD_CLIENT_SECRET"]
    )
      @client_id = client_id
      @client_secret = client_secret

      return unless @client_id.blank? || @client_secret.blank?

      raise ArgumentError,
            "Blizzard client_id and client_secret must be provided. " \
            "Set Rails credentials (blizzard.client_id / blizzard.client_secret) " \
            "or ENV BLIZZARD_CLIENT_ID / BLIZZARD_CLIENT_SECRET. " \
            "If using credentials in a worker process, ensure RAILS_MASTER_KEY is present."
    end

    def access_token
      cached = read_cache

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
        response = HTTPX.post(
          OAUTH_URL,
          form:    { grant_type: "client_credentials" },
          headers: {
            "Authorization": "Basic #{Base64.strict_encode64("#{@client_id}:#{@client_secret}")}"
          }
        )

        return response if response.status == 200

        raise Error, "Blizzard OAuth error: HTTP #{response.status}"
      end

      def parse_response_body(response)
        # Use Oj directly for ~2-3x faster JSON parsing
        Oj.load(response.body, mode: :compat)
      rescue Oj::ParseError, JSON::ParserError
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

      def read_cache
        Rails.cache&.read(CACHE_KEY)
      end

      def write_cache(token, expires_at, expires_in)
        cache = Rails.cache

        unless cache
          Rails.logger.warn("[Blizzard::Auth] Rails.cache is nil; skipping access token caching")
          return
        end

        cache.write(
          CACHE_KEY,
          { token: token, expires_at: expires_at },
          expires_in: expires_in
        )
      end
  end
end
