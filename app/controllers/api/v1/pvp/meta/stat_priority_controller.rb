class Api::V1::Pvp::Meta::StatPriorityController < Api::V1::BaseController
  before_action :validate_params!

  # GET /api/v1/pvp/meta/stat_priority
  # Returns secondary stat priority as median in-game percentages across
  # top players in the given bracket + spec.
  def show
    cache_key = meta_cache_key("stat_priority", bracket_param, spec_id_param)

    json = meta_cache_fetch(cache_key) do
      { bracket: bracket_param, spec_id: spec_id_param, stats: build_stats }
    end

    render json: json
    set_cache_headers
  end

  private

    def build_stats
      rows = stat_medians_sql
      return [] if rows.empty?

      rows.map { |stat, median| { stat: stat, median: median.to_f.round(1) } }
    end

    def stat_medians_sql
      conn = ApplicationRecord.connection
      conn.select_rows(<<~SQL.squish)
        SELECT
          kv.key AS stat,
          PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY kv.value::numeric) AS median
        FROM characters
        INNER JOIN pvp_leaderboard_entries ON pvp_leaderboard_entries.character_id = characters.id
        INNER JOIN pvp_leaderboards ON pvp_leaderboards.id = pvp_leaderboard_entries.pvp_leaderboard_id
        CROSS JOIN LATERAL jsonb_each_text(characters.stat_pcts) AS kv(key, value)
        WHERE pvp_leaderboards.bracket = #{conn.quote(bracket_param)}
          AND pvp_leaderboards.pvp_season_id = #{current_season.id.to_i}
          AND pvp_leaderboard_entries.spec_id = #{spec_id_param.to_i}
          AND characters.stat_pcts <> '{}'
        GROUP BY kv.key
        ORDER BY median DESC
      SQL
    end

    def validate_params!
      validate_bracket!(params.require(:bracket)) or return
      validate_spec_id!(params.require(:spec_id)) or return
    end

    def bracket_param
      @bracket_param ||= params.require(:bracket)
    end

    def spec_id_param
      @spec_id_param ||= params.require(:spec_id).to_i
    end
end
