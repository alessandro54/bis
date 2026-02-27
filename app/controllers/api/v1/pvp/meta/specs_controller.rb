class Api::V1::Pvp::Meta::SpecsController < Api::V1::BaseController
  # GET /api/v1/pvp/meta/specs
  # Returns spec distribution and popular talent builds for a bracket
  def index
    entries = PvpLeaderboardEntry
      .latest_snapshot_for_bracket(bracket_param)
      .where.not(spec_id: nil)
      .includes(:character)

    render json: {
      bracket:     bracket_param,
      specs:       build_spec_stats(entries),
      snapshot_at: entries.first&.snapshot_at
    }
  end

  # GET /api/v1/pvp/meta/specs/:spec_id
  # Returns detailed meta for a specific spec including talent builds
  def show
    entries = PvpLeaderboardEntry
      .latest_snapshot_for_bracket(bracket_param)
      .where(spec_id: spec_id_param)
      .includes(:character)

    render json: {
      spec_id:       spec_id_param,
      bracket:       bracket_param,
      total_players: entries.count,
      talent_builds: build_talent_stats(entries),
      hero_talents:  build_hero_talent_stats(entries),
      tier_sets:     build_tier_set_stats(entries),
      snapshot_at:   entries.first&.snapshot_at
    }
  end

  private

    def build_spec_stats(entries)
      total = entries.count.to_f
      return [] if total.zero?

      entries
        .group(:spec_id)
        .count
        .map do |spec_id, count|
          {
            spec_id:   spec_id,
            spec_slug: Wow::Catalog::SPECS[spec_id][:spec_slug],
            count:     count,
            usage_pct: (count / total * 100).round(2)
          }
        end
        .sort_by { |s| -s[:usage_pct] }
    end

    def build_talent_stats(entries)
      total = entries.count.to_f
      return [] if total.zero?

      # Group by talent_loadout_code from character
      loadout_counts = entries
        .joins(:character)
        .where.not(characters: { talent_loadout_code: nil })
        .group("characters.talent_loadout_code")
        .count

      loadout_counts
        .map do |code, count|
          {
            loadout_code: code,
            count:        count,
            usage_pct:    (count / total * 100).round(2)
          }
        end
        .sort_by { |b| -b[:usage_pct] }
        .first(limit_param)
    end

    def build_hero_talent_stats(entries)
      total = entries.count.to_f
      return [] if total.zero?

      entries
        .where.not(hero_talent_tree_id: nil)
        .group(:hero_talent_tree_id, :hero_talent_tree_name)
        .count
        .map do |(tree_id, tree_name), count|
          {
            hero_talent_tree_id:   tree_id,
            hero_talent_tree_name: tree_name,
            count:                 count,
            usage_pct:             (count / total * 100).round(2)
          }
        end
        .sort_by { |h| -h[:usage_pct] }
    end

    def build_tier_set_stats(entries)
      total = entries.count.to_f
      return [] if total.zero?

      entries
        .where.not(tier_set_id: nil)
        .group(:tier_set_id, :tier_set_name, :tier_set_pieces, :tier_4p_active)
        .count
        .map do |(set_id, set_name, pieces, is_4p), count|
          {
            tier_set_id:     set_id,
            tier_set_name:   set_name,
            tier_set_pieces: pieces,
            tier_4p_active:  is_4p,
            count:           count,
            usage_pct:       (count / total * 100).round(2)
          }
        end
        .sort_by { |t| -t[:usage_pct] }
    end

    def bracket_param
      params.require(:bracket)
    end

    def spec_id_param
      params[:id].to_i
    end

    def limit_param
      [ params[:limit]&.to_i || 20, 100 ].min
    end
end
