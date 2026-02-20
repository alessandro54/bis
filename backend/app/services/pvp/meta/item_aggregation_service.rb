module Pvp
  module Meta
    class ItemAggregationService < ApplicationService
      def initialize(season:, bracket:, snapshot_at:)
        @season      = season
        @bracket     = bracket
        @snapshot_at = snapshot_at
      end

      def call
        aggregate_item_popularity

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
        def aggregate_item_popularity
          rows = ActiveRecord::Base.connection.exec_query(<<~SQL.squish, "ItemPopularity", 
[ season.id, bracket, rating_min ])
            SELECT
              e.spec_id,
              ci.slot,
              ci.item_id,
              COUNT(*) AS usage_count,
              AVG(ci.item_level) AS avg_item_level
            FROM character_items ci
            JOIN (
              SELECT DISTINCT ON (e.character_id)
                e.character_id,
                e.spec_id
              FROM pvp_leaderboard_entries e
              JOIN pvp_leaderboards lb ON lb.id = e.pvp_leaderboard_id
              WHERE lb.pvp_season_id = $1
                AND lb.bracket = $2
                AND e.rating >= $3
                AND e.spec_id IS NOT NULL
              ORDER BY e.character_id, e.rating DESC
            ) e ON e.character_id = ci.character_id
            GROUP BY e.spec_id, ci.slot, ci.item_id
          SQL

          return if rows.empty?

          # Compute total per spec+slot for usage_pct
          totals = rows.group_by { |r| [ r["spec_id"], r["slot"] ] }
            .transform_values { |group| group.sum { |r| r["usage_count"] } }

          now = Time.current
          records = rows.map do |row|
            total = totals[[ row["spec_id"], row["slot"] ]] || 1
            {
              pvp_season_id:  season.id,
              bracket:        bracket,
              spec_id:        row["spec_id"],
              slot:           row["slot"],
              item_id:        row["item_id"],
              usage_count:    row["usage_count"],
              usage_pct:      (row["usage_count"].to_f / total * 100).round(2),
              avg_item_level: row["avg_item_level"]&.to_f&.round(2),
              snapshot_at:    snapshot_at,
              created_at:     now,
              updated_at:     now
            }
          end

          # rubocop:disable Rails/SkipsModelValidations
          PvpMetaItemPopularity.insert_all!(records)
          # rubocop:enable Rails/SkipsModelValidations
        end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
