module Pvp
  module Meta
    class ItemAggregationService < BaseService
      include AggregationSql

      TOP_N = ENV.fetch("PVP_META_TOP_N", 1000).to_i

      def initialize(season:, top_n: TOP_N, cycle: nil)
        @season = season
        @top_n  = top_n
        @cycle  = cycle
      end

      def call
        prev_map = snapshot_prev_values
        rows     = execute_query
        records  = build_records(rows, prev_map)

        ApplicationRecord.transaction do
          # rubocop:disable Rails/SkipsModelValidations
          PvpMetaItemPopularity.where(pvp_season_id: season.id).delete_all unless @cycle
          PvpMetaItemPopularity.insert_all!(records) if records.any?
          # rubocop:enable Rails/SkipsModelValidations
        end

        success(records.size, context: { count: records.size })
      rescue => e
        Sentry.capture_exception(e, extra: { service: self.class.name, season_id: season.id })
        failure(e, captured: true)
      end

      private

        attr_reader :season, :top_n, :cycle

        def execute_query
          ApplicationRecord.connection.select_all(
            ApplicationRecord.sanitize_sql_array([ item_popularity_sql, { season_id: season.id, top_n: top_n } ])
          )
        end

        def item_popularity_sql
          <<~SQL
            WITH #{top_chars_cte},
            slot_totals AS (
              SELECT t.bracket, t.spec_id, ci.slot, COUNT(*) AS total
              FROM top_chars t
              JOIN character_items ci ON ci.character_id = t.character_id AND ci.spec_id = t.spec_id
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
            JOIN character_items ci ON ci.character_id = t.character_id AND ci.spec_id = t.spec_id
            JOIN slot_totals st
              ON st.bracket = t.bracket AND st.spec_id = t.spec_id AND st.slot = ci.slot
            GROUP BY t.bracket, t.spec_id, ci.slot, ci.item_id, st.total
            ORDER BY t.bracket, t.spec_id, ci.slot, usage_count DESC
          SQL
        end

        def build_records(rows, prev_map = {})
          now = Time.current
          rows.map do |r|
            prev = prev_map[[ r["bracket"], r["spec_id"].to_i, r["slot"], r["item_id"].to_i ]]
            {
              pvp_season_id:     season.id,
              bracket:           r["bracket"],
              spec_id:           r["spec_id"],
              slot:              r["slot"],
              item_id:           r["item_id"],
              usage_count:       r["usage_count"],
              usage_pct:         r["usage_pct"],
              prev_usage_pct:    prev,
              snapshot_at:       r["snapshot_at"] || now,
              created_at:        now,
              updated_at:        now,
              pvp_sync_cycle_id: @cycle&.id
            }
          end
        end

        def snapshot_prev_values
          PvpMetaItemPopularity
            .where(pvp_season_id: season.id)
            .pluck(:bracket, :spec_id, :slot, :item_id, :usage_pct)
            .each_with_object({}) do |(bracket, spec_id, slot, item_id, pct), h|
              h[[ bracket, spec_id.to_i, slot, item_id.to_i ]] = pct
            end
        end
    end
  end
end
