module Blizzard
  module Api
    module Profile
      class CharacterStatisticsSummary < Blizzard::Api::BaseRequest
        SECONDARY_STAT_KEYS = {
          "HASTE_RATING" => ->(s) {
 { pct: s.dig("melee_haste", "rating_bonus"), rating: s.dig("melee_haste", "rating") } },
          "CRIT_RATING" => ->(s) {
 { pct: s.dig("melee_crit",  "rating_bonus"), rating: s.dig("melee_crit",  "rating") } },
          "MASTERY_RATING" => ->(s) {
 { pct: s.dig("mastery",     "rating_bonus"), rating: s.dig("mastery",     "rating") } },
          "VERSATILITY" => ->(s) { { pct: s["versatility_damage_done_bonus"], rating: s["versatility"] } }
        }.freeze

        def self.fetch(region:, name:, realm:, locale: "en_US", params: {})
          client     = client(region:, locale:)
          realm_slug = CGI.escape(realm.downcase)
          name_slug  = CGI.escape(name.downcase)
          client.get("/profile/wow/character/#{realm_slug}/#{name_slug}/statistics",
                     namespace: client.profile_namespace,
                     params:    params)
        end

        # Extracts secondary stat data from raw statistics response.
        # Returns e.g. { "VERSATILITY" => { "pct" => 14.5, "rating" => 783 }, ... }
        def self.extract_stat_pcts(raw)
          return {} unless raw.is_a?(Hash)

          SECONDARY_STAT_KEYS.each_with_object({}) do |(stat, extractor), result|
            data = extractor.call(raw)
            next unless data[:pct] && data[:rating]

            result[stat] = { "pct" => data[:pct].to_f, "rating" => data[:rating].to_i }
          end
        end
      end
    end
  end
end
