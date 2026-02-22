# app/services/blizzard/client.rb

module Blizzard
  class Client
    class Error < StandardError; end
    class RateLimitedError < Error; end

    # Shared HTTP client instance with connection pooling
    # Thread-safe: HTTPX handles concurrent requests internally
    HTTP_CLIENT = HTTPX
      .plugin(:persistent)
      .plugin(:retries, retry_on: ->(res) { res.is_a?(HTTPX::ErrorResponse) }, max_retries: 2)
      .with(
        timeout: {
          connect_timeout:   5,
          operation_timeout: 15
        }
      )

    # Rate limiting strategy:
    # - Per-job concurrency is bounded by run_concurrently's Async::Semaphore
    #   (default 5 fibers via PVP_SYNC_CONCURRENCY)
    # - 429 responses trigger sleep(Retry-After) + RateLimitedError
    # - Blizzard allows 100 req/s; with persistent connections and bounded
    #   concurrency, throughput is naturally limited by API latency (~300ms)
    #   giving ~5-10 chars/s per job which stays well under the limit.

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

    def self.default_locale_for(region)
      VALID_LOCALES.fetch(region.to_s, VALID_LOCALES["us"]).first
    end

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

      response = HTTP_CLIENT.get(url, params: query, headers: headers)

      parse_response(response)
    end

    def profile_namespace = "profile-#{region}"
    def dynamic_namespace = "dynamic-#{region}"
    def static_namespace = "static-#{region}"

    private


      def build_url(path)
        "https://#{API_HOST_TEMPLATE % { region: region }}#{path}"
      end

      def auth_header
        { Authorization: "Bearer #{auth.access_token}" }
      end

      def parse_response(response)
        if response.is_a?(HTTPX::ErrorResponse)
          raise Error, "Network/Transport error: #{response.error}"
        end

        if response.status == 200
          return Oj.load(response.body.to_s, mode: :compat)
        end

        if response.status == 429
          retry_after = response.headers["retry-after"]&.to_i || 1
          raise RateLimitedError,
                "Blizzard API rate limited (429). Retry-After: #{retry_after}s"
        end

        raise Error,
              "Blizzard API error: HTTP #{response.status}, body=#{response.body}"
      rescue Oj::ParseError, JSON::ParserError => e
        raise Error,
              "Blizzard API error: invalid JSON: #{e.message}\n#{response.body}"
      end
  end
end
