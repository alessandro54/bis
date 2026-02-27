module Pvp
  module Meta
    # Shared SQL building blocks for all three meta aggregation services.
    # The CTEs are identical across item/enchant/gem — only the SELECT and
    # GROUP BY differ. Each service calls `top_chars_cte` and appends its
    # own projection on top.
    module AggregationSql
      # Returns top N characters per bracket/spec by their highest rating
      # in the given season. Only includes characters with processed equipment.
      #
      # Exposed CTEs:
      #   top_chars  → character_id, bracket, spec_id, rating
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
              AND e.equipment_processed_at IS NOT NULL
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
    end
  end
end
