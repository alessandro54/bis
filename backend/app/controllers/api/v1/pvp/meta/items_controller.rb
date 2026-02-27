class Api::V1::Pvp::Meta::ItemsController < Api::V1::BaseController
  def index
    items = PvpMetaItemPopularity
      .includes(item: :translations)
      .where(pvp_season: current_season)
      .where(bracket: bracket_param)
      .where(spec_id: spec_id_param)
      .order(usage_pct: :desc)

    items = items.where(slot: slot_param) if slot_param.present?

    render json: items.map { |record| serialize_item(record) }
  end

  private

    def serialize_item(record)
      {
        id:          record.id,
        item:        {
          id:          record.item.id,
          blizzard_id: record.item.blizzard_id,
          name:        record.item.t("name", locale: locale_param),
          icon_url:    record.item.icon_url,
          quality:     record.item.quality
        },
        slot:        record.slot,
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

    def slot_param
      params[:slot]
    end

    def locale_param
      params[:locale] || "en_US"
    end
end
