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
      rows = stat_pct_rows
      return [] if rows.empty?

      compute_medians(rows)
        .sort_by { |_, median| -median }
        .map { |stat, median| { stat: stat, median: median.round(1) } }
    end

    def stat_pct_rows
      Character
        .joins(pvp_leaderboard_entries: :pvp_leaderboard)
        .where(pvp_leaderboards: { bracket: bracket_param, pvp_season: current_season })
        .where(pvp_leaderboard_entries: { spec_id: spec_id_param })
        .where("stat_pcts <> '{}'")
        .pluck(:stat_pcts)
    end

    # Returns { "VERSATILITY" => 347, ... } — median rating per stat across all characters.
    # rubocop:disable Metrics/AbcSize
    def compute_medians(rows)
      stat_values = Hash.new { |h, k| h[k] = [] }
      rows.each do |pcts|
        pcts.each { |stat, rating| stat_values[stat] << rating.to_i }
      end

      stat_values.transform_values do |values|
        sorted = values.sort
        mid    = sorted.size / 2
        sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
      end
    end
    # rubocop:enable Metrics/AbcSize

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
