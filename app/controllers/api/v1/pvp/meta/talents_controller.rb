class Api::V1::Pvp::Meta::TalentsController < Api::V1::BaseController
  def index
    records = PvpMetaTalentPopularity
      .includes(talent: :translations)
      .where(pvp_season: current_season)
      .where(bracket: bracket_param)
      .where(spec_id: spec_id_param)
      .order(usage_pct: :desc)

    render json: records.map { |r| serialize(r) }
  end

  private

    def serialize(record)
      {
        id:          record.id,
        talent:      {
          id:          record.talent.id,
          blizzard_id: record.talent.blizzard_id,
          name:        record.talent.t("name", locale: locale_param),
          talent_type: record.talent_type,
          spell_id:    record.talent.spell_id
        },
        usage_count: record.usage_count,
        usage_pct:   record.usage_pct.to_f,
        snapshot_at: record.snapshot_at
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
