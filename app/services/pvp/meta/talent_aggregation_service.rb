module Pvp
  module Meta
    class TalentAggregationService < BaseService
      include AggregationSql

      TOP_N = ENV.fetch("PVP_META_TOP_N", 1000).to_i

      def initialize(season:, top_n: TOP_N)
        @season = season
        @top_n  = top_n
      end

      def call
        rows    = execute_query
        records = build_records(rows)

        if records.any?
          # rubocop:disable Rails/SkipsModelValidations
          PvpMetaTalentPopularity.upsert_all(
            records,
            unique_by:   %i[pvp_season_id bracket spec_id talent_id],
            update_only: %i[talent_type usage_count usage_pct snapshot_at]
          )
          # rubocop:enable Rails/SkipsModelValidations
        end

        success(records.size, context: { count: records.size })
      rescue => e
        failure(e)
      end

      private

        attr_reader :season, :top_n

        # Override to filter on specialization_processed_at instead of equipment_processed_at
        def top_chars_cte
          <<~SQL
            latest_per_char AS (
              SELECT DISTINCT ON (l.bracket, e.character_id)
                e.character_id,
                l.bracket,
                e.spec_id,
                e.rating
              FROM pvp_leaderboard_entries e
              JOIN pvp_leaderboards l ON l.id = e.pvp_leaderboard_id
              WHERE l.pvp_season_id = :season_id
                AND e.spec_id IS NOT NULL
                AND e.specialization_processed_at IS NOT NULL
              ORDER BY l.bracket, e.character_id, e.rating DESC
            ),
            ranked AS (
              SELECT *,
                RANK() OVER (PARTITION BY bracket, spec_id ORDER BY rating DESC) AS rk
              FROM latest_per_char
            ),
            top_chars AS (
              SELECT * FROM ranked WHERE rk <= :top_n
            )
          SQL
        end

        # rubocop:disable Metrics/MethodLength
        def execute_query
          sql = <<~SQL
            WITH #{top_chars_cte},
            spec_totals AS (
              SELECT bracket, spec_id, COUNT(*) AS total
              FROM top_chars
              GROUP BY bracket, spec_id
            )
            SELECT
              t.bracket,
              t.spec_id,
              ct.talent_id,
              tal.talent_type,
              COUNT(*)                                AS usage_count,
              ROUND(COUNT(*) * 100.0 / st.total, 2)  AS usage_pct,
              NOW()                                   AS snapshot_at
            FROM top_chars t
            JOIN character_talents ct ON ct.character_id = t.character_id
            JOIN talents tal ON tal.id = ct.talent_id
            JOIN spec_totals st
              ON st.bracket = t.bracket AND st.spec_id = t.spec_id
            GROUP BY t.bracket, t.spec_id, ct.talent_id, tal.talent_type, st.total
            ORDER BY t.bracket, t.spec_id, tal.talent_type, usage_count DESC
          SQL

          ApplicationRecord.connection.select_all(
            ApplicationRecord.sanitize_sql_array([ sql, { season_id: season.id, top_n: top_n } ])
          )
        end
        # rubocop:enable Metrics/MethodLength

        def build_records(rows)
          now = Time.current
          rows.map do |r|
            {
              pvp_season_id: season.id,
              bracket:       r["bracket"],
              spec_id:       r["spec_id"],
              talent_id:     r["talent_id"],
              talent_type:   r["talent_type"],
              usage_count:   r["usage_count"],
              usage_pct:     r["usage_pct"],
              snapshot_at:   r["snapshot_at"] || now,
              created_at:    now,
              updated_at:    now
            }
          end
        end
    end
  end
end
