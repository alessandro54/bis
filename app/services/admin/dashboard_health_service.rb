module Admin
  class DashboardHealthService < BaseService
    TRANSLATION_SECTIONS = [
      { label: "Items & Gems", type: "Item" },
      { label: "Enchantments", type: "Enchantment" },
      { label: "Talents",      type: "Talent" }
    ].freeze

    def initialize(season:)
      @season = season
    end

    def call
      success(nil, context: {
        last_cycle:   last_cycle,
        brackets:     brackets,
        characters:   characters,
        freshness:    freshness,
        translations: translations
      })
    end

    private

      attr_reader :season

      # -- Sync cycle --

      def last_cycle
        PvpSyncCycle.where(pvp_season: season).order(created_at: :desc).first
      end

      # -- Per-bracket entry processing --

      def brackets
        PvpLeaderboard
          .where(pvp_season: season)
          .order(:bracket, :region)
          .group_by(&:bracket)
          .filter_map { |bracket, lbs| bracket_stats(bracket, lbs) }
      end

      # rubocop:disable Layout/LineLength, Metrics/MethodLength, Metrics/PerceivedComplexity
      def bracket_stats(bracket, lbs)
        lb_ids = lbs.map(&:id)

        total, fully, eq_only, spec_only, none = PvpLeaderboardEntry
          .where(pvp_leaderboard_id: lb_ids)
          .pick(
            Arel.sql("COUNT(*)"),
            Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at IS NOT NULL AND specialization_processed_at IS NOT NULL)"),
            Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at IS NOT NULL AND specialization_processed_at IS NULL)"),
            Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at IS NULL AND specialization_processed_at IS NOT NULL)"),
            Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at IS NULL AND specialization_processed_at IS NULL)")
          )
        return if total.zero?

        regions = lbs.map { |lb| lb.region.upcase }.sort.join(" + ")
        {
          label: bracket, regions: regions, total: total,
          rows: [
            { label: "Fully processed", count: fully,     pct: pct(fully, total) },
            { label: "Equipment only",  count: eq_only,   pct: pct(eq_only, total) },
            { label: "Talents only",    count: spec_only, pct: pct(spec_only, total) },
            { label: "Unprocessed",     count: none,      pct: pct(none, total) }
          ]
        }
      end
      # rubocop:enable Layout/LineLength, Metrics/MethodLength, Metrics/PerceivedComplexity

      # -- Character availability --

      def characters
        char_ids = PvpLeaderboardEntry
          .joins(:pvp_leaderboard)
          .where(pvp_leaderboards: { pvp_season: season })
          .distinct
          .pluck(:character_id)
        return if char_ids.empty?

        total, private_c, unavailable_c = Character.where(id: char_ids).pick(
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(*) FILTER (WHERE is_private = true)"),
          Arel.sql("COUNT(*) FILTER (WHERE unavailable_until IS NOT NULL AND unavailable_until > NOW())")
        )
        available_c = total - private_c - unavailable_c

        {
          total: total,
          rows:  [
            { label: "Available",       count: available_c,   pct: pct(available_c, total) },
            { label: "Not found (404)", count: unavailable_c, pct: pct(unavailable_c, total) },
            { label: "Private",         count: private_c,     pct: pct(private_c, total) }
          ]
        }
      end

      # -- Data freshness --

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Layout/LineLength
      def freshness
        scope = PvpLeaderboardEntry
        .joins(:pvp_leaderboard)
        .where(pvp_leaderboards: { pvp_season: season })
          .where.not(equipment_processed_at: nil)

        total, h1, h6, h24, older = scope.pick(
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at > NOW() - INTERVAL '1 hour')"),
          Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at BETWEEN NOW() - INTERVAL '6 hours' AND NOW() - INTERVAL '1 hour')"),
          Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at BETWEEN NOW() - INTERVAL '24 hours' AND NOW() - INTERVAL '6 hours')"),
          Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at <= NOW() - INTERVAL '24 hours')")
        )
        return unless total&.positive?

        {
          total: total,
          rows:  [
            { label: "< 1h ago",  count: h1,    pct: pct(h1, total) },
            { label: "1-6h ago",  count: h6,    pct: pct(h6, total) },
            { label: "6-24h ago", count: h24,   pct: pct(h24, total) },
            { label: "> 24h ago", count: older, pct: pct(older, total) }
          ]
        }
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Layout/LineLength

      # -- Translation coverage --

      def translations
        TRANSLATION_SECTIONS.map { |s| translation_section(s) }
      end

      def translation_section(config)
        ids     = meta_ids_for(config[:type])
        locales = Wow::Locales::SUPPORTED_LOCALES.map { |locale| locale_stats(config[:type], ids, locale) }
        { label: config[:label], total: ids.size, locales: locales }
      end

      def meta_ids_for(type)
        case type
        when "Item"
          (PvpMetaItemPopularity.where(pvp_season: season).distinct.pluck(:item_id) +
           PvpMetaGemPopularity.where(pvp_season: season).distinct.pluck(:item_id)).uniq
        when "Enchantment"
          PvpMetaEnchantPopularity.where(pvp_season: season).distinct.pluck(:enchantment_id)
        when "Talent"
          PvpMetaTalentPopularity.where(pvp_season: season).distinct.pluck(:talent_id)
        end
      end

      def locale_stats(type, ids, locale)
        present = ids.empty? ? 0 : Translation
          .where(translatable_type: type, translatable_id: ids, locale: locale, key: "name")
          .count
        missing = ids.size - present

        { locale: locale, present: present, missing: missing, pct: pct(present, ids.size) }
      end

      def pct(count, total)
        total > 0 ? (count.to_f / total * 100).round(1) : 100.0
      end
  end
end
