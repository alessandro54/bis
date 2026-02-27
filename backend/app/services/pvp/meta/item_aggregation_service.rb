module Pvp
  module Meta
    class ItemAggregationService < BaseService
      include AggregationSql

      TOP_N = ENV.fetch("PVP_META_TOP_N", 1000).to_i

      def initialize(season:, top_n: TOP_N)
        @season = season
        @top_n  = top_n
      end

      def call
        rows    = execute_query
        records = build_records(rows)

        ApplicationRecord.transaction do
          PvpMetaItemPopularity.where(pvp_season_id: season.id).delete_all
          # rubocop:disable Rails/SkipsModelValidations
          PvpMetaItemPopularity.insert_all!(records) if records.any?
          # rubocop:enable Rails/SkipsModelValidations
        end

        success(records.size, context: { count: records.size })
      rescue => e
        failure(e)
      end

      private

        attr_reader :season, :top_n

        # rubocop:disable Metrics/MethodLength
        def execute_query
          sql = <<~SQL
            WITH #{top_chars_cte},
            slot_totals AS (
              SELECT t.bracket, t.spec_id, ci.slot, COUNT(*) AS total
              FROM top_chars t
              JOIN character_items ci ON ci.character_id = t.character_id
              GROUP BY t.bracket, t.spec_id, ci.slot
            )
            SELECT
              t.bracket,
              t.spec_id,
              ci.slot,
              ci.item_id,
              COUNT(*)                                  AS usage_count,
              ROUND(COUNT(*) * 100.0 / st.total, 2)    AS usage_pct,
              NOW()                                     AS snapshot_at
            FROM top_chars t
            JOIN character_items ci ON ci.character_id = t.character_id
            JOIN slot_totals st
              ON st.bracket = t.bracket AND st.spec_id = t.spec_id AND st.slot = ci.slot
            GROUP BY t.bracket, t.spec_id, ci.slot, ci.item_id, st.total
            ORDER BY t.bracket, t.spec_id, ci.slot, usage_count DESC
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
              slot:          r["slot"],
              item_id:       r["item_id"],
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
