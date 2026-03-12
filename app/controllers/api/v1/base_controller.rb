class Api::V1::BaseController < ApplicationController
  private

    META_CACHE_TTL = 30.minutes
    META_CACHE_VERSION_KEY = "pvp_meta/version"

    # Builds a versioned cache key so all meta caches can be busted at once
    # by incrementing the version.
    def meta_cache_key(*segments)
      version = Rails.cache.read(META_CACHE_VERSION_KEY) || 0
      "pvp_meta/v#{version}/#{segments.compact.join("/")}"
    end

    # Wraps Rails.cache.fetch but skips caching entirely in development
    # so controllers always return fresh data.
    def meta_cache_fetch(cache_key, expires_in: META_CACHE_TTL, &block)
      return yield if Rails.env.development?

      Rails.cache.fetch(cache_key, expires_in: expires_in, &block)
    end

    # Sets Cache-Control for CDN/browser caching.
    def set_cache_headers(max_age: 5.minutes, stale_while_revalidate: 1.hour)
      expires_in max_age, public: true, stale_while_revalidate: stale_while_revalidate
    end

    def current_season
      @current_season ||= PvpSeason.current
    end

    def locale_param
      loc = params[:locale]
      Wow::Locales::SUPPORTED_LOCALES.include?(loc) ? loc : "en_US"
    end
end
