class Api::V1::Pvp::Meta::StatsController < Api::V1::BaseController
  before_action :validate_params!

  def index
    cache_key = meta_cache_key("stats", bracket_param, spec_id_param)
    json = meta_cache_fetch(cache_key) { serialize_stats_response }
    render json: json
    set_cache_headers
  end

  private

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

    def serialize_stats_response
      season = meta_season_for(PvpMetaItemPopularity)
      row    = Pvp::Meta::CharacterStatsService.new(
        season:  season,
        bracket: bracket_param,
        spec_id: spec_id_param
      ).call || {}
      serialize_stat_row(row)
    end

    def serialize_stat_row(row)
      {
        avg_ilvl: row["avg_ilvl"]&.to_i,
        stats:    {
          "VERSATILITY" => row["versatility"]&.to_i || 0,
          "MASTERY_RATING" => row["mastery"]&.to_i || 0,
          "HASTE_RATING" => row["haste"]&.to_i || 0,
          "CRIT_RATING" => row["crit"]&.to_i || 0
        }
      }
    end
end
