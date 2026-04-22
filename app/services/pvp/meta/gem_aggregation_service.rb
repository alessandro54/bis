module Pvp
  module Meta
    class GemAggregationService < BaseService
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
          PvpMetaGemPopularity.where(pvp_season_id: season.id).delete_all unless @cycle
          PvpMetaGemPopularity.insert_all!(records) if records.any?
          # rubocop:enable Rails/SkipsModelValidations
        end

        success(records.size, context: { count: records.size })
      rescue => e
        Sentry.capture_exception(e, extra: { service: self.class.name, season_id: season.id })
        failure(e, captured: true)
      end

      private

        attr_reader :season, :top_n, :cycle

        def snapshot_prev_values
          PvpMetaGemPopularity
            .where(pvp_season_id: season.id)
            .pluck(:bracket, :spec_id, :slot, :socket_type, :item_id, :usage_pct)
            .each_with_object({}) do |(bracket, spec_id, slot, socket_type, item_id, pct), h|
              h[[ bracket, spec_id.to_i, slot, socket_type, item_id.to_i ]] = pct
            end
        end

        def execute_query
          ApplicationRecord.connection.select_all(
            ApplicationRecord.sanitize_sql_array([ gem_popularity_sql, { season_id: season.id, top_n: top_n } ])
          )
        end

        def gem_popularity_sql
          <<~SQL
            WITH #{top_chars_cte},
            slot_totals AS (
              SELECT t.bracket, t.spec_id, ci.slot, COUNT(DISTINCT t.character_id) AS total
              FROM top_chars t
              JOIN character_items ci ON ci.character_id = t.character_id AND ci.spec_id = t.spec_id
              WHERE jsonb_array_length(ci.sockets) > 0
              GROUP BY t.bracket, t.spec_id, ci.slot
            ),
            gem_per_char AS (
              SELECT DISTINCT
                t.bracket,
                t.spec_id,
                ci.slot,
                socket->>'type'              AS socket_type,
                (socket->>'item_id')::bigint AS item_id,
                t.character_id
              FROM top_chars t
              JOIN character_items ci ON ci.character_id = t.character_id AND ci.spec_id = t.spec_id
              JOIN jsonb_array_elements(ci.sockets) AS socket ON TRUE
              WHERE socket->>'item_id' IS NOT NULL
                AND socket->>'type'    IS NOT NULL
            )
            SELECT
              g.bracket,
              g.spec_id,
              g.slot,
              g.socket_type,
              g.item_id,
              COUNT(*)                                       AS usage_count,
              ROUND(COUNT(*) * 100.0 / st.total, 2)         AS usage_pct,
              NOW()                                          AS snapshot_at
            FROM gem_per_char g
            JOIN slot_totals st
              ON st.bracket = g.bracket AND st.spec_id = g.spec_id AND st.slot = g.slot
            GROUP BY
              g.bracket, g.spec_id, g.slot, g.socket_type, g.item_id, st.total
            ORDER BY g.bracket, g.spec_id, g.slot, g.socket_type, usage_count DESC
          SQL
        end

        def build_records(rows, prev_map = {})
          now = Time.current
          rows.map { |r| build_record(r, prev_map, now) }
        end

        def build_record(r, prev_map, now)
          prev = prev_map[[ r["bracket"], r["spec_id"].to_i, r["slot"], r["socket_type"], r["item_id"].to_i ]]
          {
            pvp_season_id:     season.id,
            bracket:           r["bracket"],
            spec_id:           r["spec_id"],
            slot:              r["slot"],
            socket_type:       r["socket_type"],
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
  end
end
