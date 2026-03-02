class Api::V1::Pvp::Meta::TalentsController < Api::V1::BaseController
  def index
    records = PvpMetaTalentPopularity
      .includes(talent: :translations)
      .where(pvp_season: current_season)
      .where(bracket: bracket_param)
      .where(spec_id: spec_id_param)
      .order(usage_pct: :desc)

    zero_talents = load_zero_fill_talents(records)
    all_talents  = records.map(&:talent) + zero_talents

    prereqs = load_prerequisites(all_talents)

    render json: records.map { |r| serialize(r, prereqs) } +
                 zero_talents.map { |t| serialize_zero(t, prereqs) }
  end

  private

    def load_zero_fill_talents(records)
      existing_ids = records.map(&:talent_id)

      base = Talent
        .includes(:translations)
        .joins(:talent_spec_assignments)
        .where(talent_spec_assignments: { spec_id: spec_id_param })

      base = base.where.not(id: existing_ids) if existing_ids.any?
      base.to_a
    end

    def load_prerequisites(talents)
      node_ids = talents.filter_map(&:node_id).uniq
      return {} if node_ids.empty?

      TalentPrerequisite
        .where(node_id: node_ids)
        .group_by(&:node_id)
        .transform_values { |ps| ps.map(&:prerequisite_node_id) }
    end

    def serialize(record, prereqs)
      t = record.talent
      {
        id:           record.id,
        talent:       serialize_talent_fields(t, record.talent_type, prereqs),
        usage_count:  record.usage_count,
        usage_pct:    record.usage_pct.to_f,
        in_top_build: record.in_top_build,
        snapshot_at:  record.snapshot_at
      }
    end

    def serialize_zero(talent, prereqs)
      {
        id:           nil,
        talent:       serialize_talent_fields(talent, talent.talent_type, prereqs),
        usage_count:  0,
        usage_pct:    0.0,
        in_top_build: false,
        snapshot_at:  nil
      }
    end

    def serialize_talent_fields(t, talent_type, prereqs)
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
        prerequisite_node_ids: prereqs[t.node_id] || []
      }
    end

    def current_season
      @current_season ||= PvpSeason.current
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
