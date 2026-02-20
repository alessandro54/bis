module Pvp
  module Meta
    class TalentAggregationService < ApplicationService
      def initialize(season:, bracket:, snapshot_at:)
        @season      = season
        @bracket     = bracket
        @snapshot_at = snapshot_at
      end

      def call
        aggregate_talent_builds
        aggregate_talent_picks
        aggregate_hero_trees

        success(nil)
      rescue => e
        failure(e)
      end

      private

        attr_reader :season, :bracket, :snapshot_at

        def rating_min
          Pvp::BracketConfig.for(bracket)&.dig(:rating_min) || 0
        end

        # rubocop:disable Metrics/MethodLength
        def aggregate_talent_builds
          rows = ActiveRecord::Base.connection.exec_query(<<~SQL.squish, "TalentBuilds", 
[ season.id, bracket, rating_min ])
            SELECT
              e.spec_id,
              c.talent_loadout_code,
              COUNT(*) AS usage_count,
              AVG(e.rating) AS avg_rating,
              SUM(e.wins)::float / NULLIF(SUM(e.wins + e.losses), 0) AS avg_winrate
            FROM pvp_leaderboard_entries e
            JOIN characters c ON c.id = e.character_id
            JOIN pvp_leaderboards lb ON lb.id = e.pvp_leaderboard_id
            WHERE lb.pvp_season_id = $1
              AND lb.bracket = $2
              AND e.rating >= $3
              AND e.spec_id IS NOT NULL
              AND c.talent_loadout_code IS NOT NULL
            GROUP BY e.spec_id, c.talent_loadout_code
          SQL

          return if rows.empty?

          # Compute total entries per spec for usage_pct
          totals_by_spec = rows.group_by { |r| r["spec_id"] }
            .transform_values { |group| group.sum { |r| r["usage_count"] } }

          now = Time.current
          records = rows.map do |row|
            total = totals_by_spec[row["spec_id"]] || 1
            {
              pvp_season_id:       season.id,
              bracket:             bracket,
              spec_id:             row["spec_id"],
              talent_loadout_code: row["talent_loadout_code"],
              usage_count:         row["usage_count"],
              usage_pct:           (row["usage_count"].to_f / total * 100).round(2),
              avg_rating:          row["avg_rating"]&.to_f&.round(2),
              avg_winrate:         row["avg_winrate"]&.to_f&.round(4),
              total_entries:       total,
              snapshot_at:         snapshot_at,
              created_at:          now,
              updated_at:          now
            }
          end

          # rubocop:disable Rails/SkipsModelValidations
          PvpMetaTalentBuild.insert_all!(records)
          # rubocop:enable Rails/SkipsModelValidations
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def aggregate_talent_picks
          rows = ActiveRecord::Base.connection.exec_query(<<~SQL.squish, "TalentPicks", 
[ season.id, bracket, rating_min ])
            SELECT
              e.spec_id,
              ct.talent_id,
              ct.talent_type,
              COUNT(*) AS usage_count,
              AVG(e.rating) AS avg_rating
            FROM character_talents ct
            JOIN pvp_leaderboard_entries e ON e.character_id = ct.character_id
            JOIN pvp_leaderboards lb ON lb.id = e.pvp_leaderboard_id
            WHERE lb.pvp_season_id = $1
              AND lb.bracket = $2
              AND e.rating >= $3
              AND e.spec_id IS NOT NULL
            GROUP BY e.spec_id, ct.talent_id, ct.talent_type
          SQL

          return if rows.empty?

          # Compute total distinct entries per spec for pick_rate
          spec_totals = ActiveRecord::Base.connection.exec_query(<<~SQL.squish, "SpecTotals", 
[ season.id, bracket, rating_min ])
            SELECT e.spec_id, COUNT(DISTINCT e.id) AS total
            FROM pvp_leaderboard_entries e
            JOIN pvp_leaderboards lb ON lb.id = e.pvp_leaderboard_id
            WHERE lb.pvp_season_id = $1
              AND lb.bracket = $2
              AND e.rating >= $3
              AND e.spec_id IS NOT NULL
            GROUP BY e.spec_id
          SQL

          totals_by_spec = spec_totals.to_h { |r| [ r["spec_id"], r["total"].to_f ] }

          now = Time.current
          records = rows.map do |row|
            total = totals_by_spec[row["spec_id"]] || 1.0
            {
              pvp_season_id: season.id,
              bracket:       bracket,
              spec_id:       row["spec_id"],
              talent_id:     row["talent_id"],
              talent_type:   row["talent_type"],
              usage_count:   row["usage_count"],
              pick_rate:     (row["usage_count"].to_f / total).round(4),
              avg_rating:    row["avg_rating"]&.to_f&.round(2),
              snapshot_at:   snapshot_at,
              created_at:    now,
              updated_at:    now
            }
          end

          # rubocop:disable Rails/SkipsModelValidations
          PvpMetaTalentPick.insert_all!(records)
          # rubocop:enable Rails/SkipsModelValidations
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength
        def aggregate_hero_trees
          rows = ActiveRecord::Base.connection.exec_query(<<~SQL.squish, "HeroTrees", [ season.id, bracket, rating_min ])
            SELECT
              e.spec_id,
              e.hero_talent_tree_id,
              e.hero_talent_tree_name,
              COUNT(*) AS usage_count,
              AVG(e.rating) AS avg_rating,
              SUM(e.wins)::float / NULLIF(SUM(e.wins + e.losses), 0) AS avg_winrate
            FROM pvp_leaderboard_entries e
            JOIN pvp_leaderboards lb ON lb.id = e.pvp_leaderboard_id
            WHERE lb.pvp_season_id = $1
              AND lb.bracket = $2
              AND e.rating >= $3
              AND e.spec_id IS NOT NULL
              AND e.hero_talent_tree_id IS NOT NULL
            GROUP BY e.spec_id, e.hero_talent_tree_id, e.hero_talent_tree_name
          SQL

          return if rows.empty?

          totals_by_spec = rows.group_by { |r| r["spec_id"] }
            .transform_values { |group| group.sum { |r| r["usage_count"] } }

          now = Time.current
          records = rows.map do |row|
            total = totals_by_spec[row["spec_id"]] || 1
            {
              pvp_season_id:         season.id,
              bracket:               bracket,
              spec_id:               row["spec_id"],
              hero_talent_tree_id:   row["hero_talent_tree_id"],
              hero_talent_tree_name: row["hero_talent_tree_name"],
              usage_count:           row["usage_count"],
              usage_pct:             (row["usage_count"].to_f / total * 100).round(2),
              avg_rating:            row["avg_rating"]&.to_f&.round(2),
              avg_winrate:           row["avg_winrate"]&.to_f&.round(4),
              snapshot_at:           snapshot_at,
              created_at:            now,
              updated_at:            now
            }
          end

          # rubocop:disable Rails/SkipsModelValidations
          PvpMetaHeroTree.insert_all!(records)
          # rubocop:enable Rails/SkipsModelValidations
        end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
