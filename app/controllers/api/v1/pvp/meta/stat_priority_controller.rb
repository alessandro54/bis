class Api::V1::Pvp::Meta::StatPriorityController < Api::V1::BaseController
  # GET /api/v1/pvp/meta/stat_priority
  # Returns secondary stat priority inferred from crafting stat choices of
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
      rows = crafting_stat_rows
      stat_counts = count_stats(rows)
      total = stat_counts.values.sum.to_f

      stat_counts.sort_by { |_, count| -count }.map do |stat, count|
        { stat: stat, count: count, pct: total > 0 ? (count / total * 100).round(1) : 0.0 }
      end
    end

    def crafting_stat_rows
      CharacterItem
        .joins(character: { pvp_leaderboard_entries: :pvp_leaderboard })
        .where(pvp_leaderboards: { bracket: bracket_param, pvp_season: current_season })
        .where(pvp_leaderboard_entries: { spec_id: spec_id_param })
        .where("crafting_stats <> '{}'")
        .pluck(:crafting_stats)
    end

    def count_stats(rows)
      rows.each_with_object(Hash.new(0)) do |stats, counts|
        stats.each { |s| counts[s] += 1 }
      end
    end

    def bracket_param
      params.require(:bracket)
    end

    def spec_id_param
      params.require(:spec_id).to_i
    end
end
