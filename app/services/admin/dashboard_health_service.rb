module Admin
  # rubocop:disable Metrics/ClassLength
  class DashboardHealthService < BaseService
    TRANSLATION_SECTIONS = [
      { label: "Items & Gems", type: "Item" },
      { label: "Enchantments", type: "Enchantment" },
      { label: "Talents",      type: "Talent" }
    ].freeze

    CLASS_COLORS = {
      "warrior" => "#C79C6E",
      "paladin" => "#F58CBA",
      "hunter" => "#ABD473",
      "rogue" => "#FFF569",
      "priest" => "#D2D2D2",
      "death_knight" => "#C41F3B",
      "shaman" => "#0070DE",
      "mage" => "#69CCF0",
      "warlock" => "#9482C9",
      "monk" => "#00FF96",
      "druid" => "#FF7D0A",
      "demon_hunter" => "#A330C9",
      "evoker" => "#33937F"
    }.freeze

    def initialize(season:)
      @season = season
    end

    def call
      success(nil, context: {
        last_cycle:   last_cycle,
        brackets:     brackets,
        characters:   characters,
        freshness:    freshness,
        translations: translations,
        leaderboard:  leaderboard_distribution
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

        total, h1, h6, h24, older = scope.pick(
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(*) FILTER (WHERE pvp_leaderboard_entries.updated_at > NOW() - INTERVAL '1 hour')"),
          Arel.sql("COUNT(*) FILTER (WHERE pvp_leaderboard_entries.updated_at BETWEEN NOW() - INTERVAL '6 hours' AND NOW() - INTERVAL '1 hour')"),
          Arel.sql("COUNT(*) FILTER (WHERE pvp_leaderboard_entries.updated_at BETWEEN NOW() - INTERVAL '24 hours' AND NOW() - INTERVAL '6 hours')"),
          Arel.sql("COUNT(*) FILTER (WHERE pvp_leaderboard_entries.updated_at <= NOW() - INTERVAL '24 hours')")
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

      # -- Leaderboard spec distribution --

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def leaderboard_distribution
        raw = PvpLeaderboardEntry
          .joins(:pvp_leaderboard)
          .where(pvp_leaderboards: { pvp_season: season })
          .where.not(pvp_leaderboard_entries: { spec_id: nil })
          .group("pvp_leaderboards.bracket", "pvp_leaderboards.region", "pvp_leaderboard_entries.spec_id")
          .pluck(
            "pvp_leaderboards.bracket",
            "pvp_leaderboards.region",
            "pvp_leaderboard_entries.spec_id",
            Arel.sql("COUNT(*)")
          )

        nested = raw.each_with_object({}) do |(bracket, region, spec_id, count), acc|
          (acc[bracket] ||= {})[region] ||= {}
          acc[bracket][region][spec_id] = count
        end

        shuffle_brackets = nested.select { |b, _| b =~ /\Ashuffle-[^o]/ }
        regular_brackets = nested.reject { |b, _| b.start_with?("shuffle-") }

        { regular: build_regular_cards(regular_brackets), shuffle: build_shuffle_by_class(shuffle_brackets) }
      end

      # rubocop:disable Metrics/PerceivedComplexity
      def build_regular_cards(brackets)
        order = { "2v2" => 0, "3v3" => 1, "rbg" => 2, "blitz-overall" => 3 }

        brackets.map do |bracket, regions|
          spec_counts = {}
          regions.each do |region, specs|
            specs.each { |sid, count| (spec_counts[sid] ||= { us: 0, eu: 0 })[region.to_sym] += count }
          end

          total       = spec_counts.values.sum { |v| v[:us] + v[:eu] }
          all_regions = regions.keys.map(&:upcase).sort.join(" + ")

          specs = spec_counts.map do |spec_id, counts|
            info  = Wow::Catalog::SPECS[spec_id] || {}
            combo = counts[:us] + counts[:eu]
            {
              spec_slug:  info[:spec_slug]  || "unknown",
              class_slug: info[:class_slug] || "unknown",
              role:       info[:role]       || :dps,
              color:      CLASS_COLORS.fetch(info[:class_slug].to_s, "#9ca3af"),
              us:         counts[:us],
              eu:         counts[:eu],
              total:      combo,
              pct:        total > 0 ? (combo.to_f / total * 100).round(1) : 0.0
            }
          end.sort_by { |s| -s[:total] }

          { bracket: bracket, regions: all_regions, total: total, specs: specs, sort: order.fetch(bracket, 10) }
        end.sort_by { |c| c[:sort] }
      end
      # rubocop:enable Metrics/PerceivedComplexity

      # rubocop:disable Metrics/PerceivedComplexity
      def build_shuffle_by_class(shuffle_brackets)
        class_data = {}

        shuffle_brackets.each do |bracket, regions|
          spec_id = Wow::Catalog.spec_id_from_bracket(bracket)
          next unless spec_id

          info = Wow::Catalog::SPECS[spec_id]
          next unless info

          us = regions.dig("us", spec_id).to_i
          eu = regions.dig("eu", spec_id).to_i

          (class_data[info[:class_slug]] ||= []) << {
            spec_id:   spec_id,
            spec_slug: info[:spec_slug],
            role:      info[:role] || :dps,
            color:     CLASS_COLORS.fetch(info[:class_slug], "#9ca3af"),
            us:        us,
            eu:        eu,
            total:     us + eu
          }
        end

        class_data
          .transform_values { |specs| specs.sort_by { |s| s[:spec_id] } }
          .sort_by { |cs, _| cs }
          .to_h
      end
      # rubocop:enable Metrics/PerceivedComplexity

      def pct(count, total)
        total > 0 ? (count.to_f / total * 100).round(1) : 100.0
      end
  end
end
# rubocop:enable Metrics/ClassLength
