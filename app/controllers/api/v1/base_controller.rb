class Api::V1::BaseController < ApplicationController
  private

    META_CACHE_TTL = 6.hours
    META_CACHE_VERSION_KEY = "pvp_meta/version"

    # Builds a versioned cache key so all meta caches can be busted at once
    # by incrementing the version.
    def meta_cache_key(*segments)
      version = Rails.cache.read(META_CACHE_VERSION_KEY) || 0
      "pvp_meta/v#{version}/#{segments.compact.join("/")}"
    end

    def current_season
      @current_season ||= PvpSeason.current
    end
end
