class Api::V1::Pvp::Meta::TalentsController < Api::V1::BaseController
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def index
    cache_key = meta_cache_key("talents", bracket_param, spec_id_param, locale_param)

    json = meta_cache_fetch(cache_key) do
      records = PvpMetaTalentPopularity
        .includes(talent: :translations)
        .where(pvp_season: current_season)
        .where(bracket: bracket_param)
        .where(spec_id: spec_id_param)
        .order(usage_pct: :desc)

      # Blizzard assigns a distinct talent_id per rank, so the same tree node
      # can produce multiple records. Merge them into one per node+name.
      records = merge_ranked_records(records.to_a)

      zero_talents = load_zero_fill_talents(records)
      all_talents  = records.map(&:talent) + zero_talents

      prereqs        = load_prerequisites(all_talents)
      default_points = load_default_points(all_talents)

      talents = records.map { |r| serialize(r, prereqs, default_points) } +
        zero_talents.map { |t| serialize_zero(t, prereqs, default_points) }

      total_weighted = records.sum(&:usage_count).to_i
      total_players  = count_raw_players

      {
        meta:    {
          bracket:        bracket_param,
          spec_id:        spec_id_param,
          total_players:  total_players,
          total_weighted: total_weighted,
          snapshot_at:    records.first&.snapshot_at
        },
        talents: talents
      }
    end

    render json: json
    set_cache_headers
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  private

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def merge_ranked_records(records)
      records
        .group_by { |r| [ r.talent.node_id, r.talent.t("name", locale: "en_US") ] }
        .flat_map do |(node_id, _name), group|
          next group if node_id.nil? || group.size == 1

          # Same node + same name = different Blizzard rank IDs for the same talent.
          # Merge into the highest-usage record, summing counts and pcts.
          primary = group.max_by { |r| r.usage_pct.to_f }
          primary.usage_count    = group.sum(&:usage_count)
          primary.usage_pct      = group.sum { |r| r.usage_pct.to_f }
          primary.in_top_build   = group.any?(&:in_top_build)
          non_zero_ranks         = group.map(&:top_build_rank).select { |r| r > 0 }
          primary.top_build_rank = non_zero_ranks.min || 0
          [ primary ]
        end
        .sort_by { |r| -r.usage_pct.to_f }
    end

    def load_zero_fill_talents(records)
      existing_ids = records.map(&:talent_id)

      # Track (node_id, name) pairs already covered by a record so we can
      # exclude stale rank variants from the zero-fill list.
      covered_nodes = records.each_with_object(Set.new) do |r, set|
        node_id = r.talent.node_id
        set.add([ node_id, r.talent.t("name", locale: "en_US") ]) if node_id
      end

      # Class/spec/hero talents from tree assignments
      tree_talents = Talent
        .includes(:translations)
        .joins(:talent_spec_assignments)
        .where(talent_spec_assignments: { spec_id: spec_id_param })
      tree_talents = tree_talents.where.not(id: existing_ids) if existing_ids.any?

      # Drop old rank variants whose node is already covered, then deduplicate
      # remaining by (node_id, name), keeping the entry with the most data.
      tree_talents = tree_talents
        .to_a
        .reject { |t| t.node_id && covered_nodes.include?([ t.node_id, t.t("name", locale: "en_US") ]) }
        .group_by { |t| [ t.node_id, t.t("name", locale: "en_US") ] }
        .flat_map { |_, group| group.size == 1 ? group : [ group.max_by { |t| t.icon_url ? 1 : 0 } ] }

      # PvP talents known for this spec (from character loadouts)
      pvp_talent_ids = CharacterTalent
        .where(spec_id: spec_id_param, talent_type: "pvp")
        .distinct.pluck(:talent_id)
      pvp_talent_ids -= existing_ids if existing_ids.any?
      pvp_talent_ids -= tree_talents.map(&:id)

      pvp_talents = pvp_talent_ids.any? ? Talent.includes(:translations).where(id: pvp_talent_ids).to_a : []

      tree_talents + pvp_talents
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def count_raw_players
      PvpLeaderboardEntry
        .joins(:pvp_leaderboard)
        .where(pvp_leaderboards: { pvp_season_id: current_season.id, bracket: bracket_param })
        .where(spec_id: spec_id_param)
        .where.not(specialization_processed_at: nil)
        .select(:character_id).distinct.count
    end

    def load_prerequisites(talents)
      node_ids = talents.filter_map(&:node_id).uniq
      return {} if node_ids.empty?

      TalentPrerequisite
        .where(node_id: node_ids)
        .group_by(&:node_id)
        .transform_values { |ps| ps.map(&:prerequisite_node_id) }
    end

    def load_default_points(talents)
      talent_ids = talents.map(&:id).uniq
      return {} if talent_ids.empty?

      TalentSpecAssignment
        .where(talent_id: talent_ids, spec_id: spec_id_param)
        .pluck(:talent_id, :default_points)
        .to_h
    end

    def serialize(record, prereqs, default_points)
      t = record.talent
      {
        id:             record.id,
        talent:         serialize_talent_fields(t, record.talent_type, prereqs, default_points),
        usage_count:    record.usage_count,
        usage_pct:      record.usage_pct.to_f,
        in_top_build:   record.in_top_build,
        top_build_rank: record.top_build_rank,
        tier:           record.tier,
        snapshot_at:    record.snapshot_at
      }
    end

    def serialize_zero(talent, prereqs, default_points)
      dp = default_points[talent.id] || 0
      {
        id:             nil,
        talent:         serialize_talent_fields(talent, talent.talent_type, prereqs, default_points),
        usage_count:    0,
        usage_pct:      0.0,
        in_top_build:   false,
        top_build_rank: 0,
        tier:           dp > 0 ? "bis" : "common",
        snapshot_at:    nil
      }
    end

    def serialize_talent_fields(t, talent_type, prereqs, default_points)
      {
        id:                    t.id,
        blizzard_id:           t.blizzard_id,
        name:                  t.t("name", locale: locale_param),
        description:           t.t("description", locale: locale_param),
        talent_type:           talent_type,
        spell_id:              t.spell_id,
        node_id:               t.node_id,
        display_row:           t.display_row,
        display_col:           t.display_col,
        max_rank:              t.max_rank,
        icon_url:              t.icon_url,
        default_points:        default_points[t.id] || 0,
        prerequisite_node_ids: prereqs[t.node_id] || []
      }
    end

    def bracket_param
      params.require(:bracket)
    end

    def spec_id_param
      params.require(:spec_id).to_i
    end

    def locale_param
      params[:locale] || "en_US"
    end
end
