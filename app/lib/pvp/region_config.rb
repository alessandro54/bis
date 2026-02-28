module Pvp
  module RegionConfig
    REGIONS = %w[us eu].freeze

    # Each region gets its own SolidQueue worker so US and EU API calls never
    # compete for the same worker — and a rate-limit hit on one region doesn't
    # stall the other.
    REGION_QUEUES = {
      "us" => :character_sync_us,
      "eu" => :character_sync_eu
    }.freeze

    REGION_LOCALES = {
      "us" => "en_US",
      "eu" => "en_GB"
    }.freeze
  end
end
