module Pvp
  module Meta
    class GemAggregationService < BaseService
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
          PvpMetaGemPopularity.where(pvp_season_id: season.id).delete_all
          PvpMetaGemPopularity.insert_all!(records) if records.any?
        end

        success(records.size, context: { count: records.size })
      rescue => e
        failure(e)
      end

      private

        attr_reader :season, :top_n

        def execute_query
          # jsonb_array_elements unnests each socket into a row.
          # slot_totals counts chars with at least one socket per slot
          # (denominator for usage_pct relative to socketed characters).
          sql = <<~SQL
            WITH #{top_chars_cte},
            slot_totals AS (
              SELECT t.bracket, t.spec_id, ci.slot, COUNT(*) AS total
              FROM top_chars t
              JOIN character_items ci ON ci.character_id = t.character_id
              WHERE jsonb_array_length(ci.sockets) > 0
              GROUP BY t.bracket, t.spec_id, ci.slot
            )
            SELECT
              t.bracket,
              t.spec_id,
              ci.slot,
              socket->>'type'               AS socket_type,
              (socket->>'item_id')::bigint  AS item_id,
              COUNT(*)                      AS usage_count,
              ROUND(COUNT(*) * 100.0 / st.total, 2) AS usage_pct,
              NOW()                         AS snapshot_at
            FROM top_chars t
            JOIN character_items ci ON ci.character_id = t.character_id
            JOIN jsonb_array_elements(ci.sockets) AS socket ON TRUE
            JOIN slot_totals st
              ON st.bracket = t.bracket AND st.spec_id = t.spec_id AND st.slot = ci.slot
            WHERE socket->>'item_id' IS NOT NULL
              AND socket->>'type'    IS NOT NULL
            GROUP BY
              t.bracket, t.spec_id, ci.slot,
              socket->>'type', (socket->>'item_id')::bigint,
              st.total
            ORDER BY t.bracket, t.spec_id, ci.slot, socket->>'type', usage_count DESC
          SQL

          ApplicationRecord.connection.select_all(
            ApplicationRecord.sanitize_sql_array([ sql, { season_id: season.id, top_n: top_n } ])
          )
        end

        def build_records(rows)
          now = Time.current
          rows.map do |r|
            {
              pvp_season_id: season.id,
              bracket:       r["bracket"],
              spec_id:       r["spec_id"],
              slot:          r["slot"],
              socket_type:   r["socket_type"],
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
