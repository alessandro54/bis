class Api::V1::Pvp::Meta::EnchantsController < Api::V1::BaseController
  def index
    enchants = PvpMetaEnchantPopularity
      .includes(enchantment: :translations)
      .where(pvp_season: current_season)
      .where(bracket: bracket_param)
      .where(spec_id: spec_id_param)
      .order(usage_pct: :desc)

    enchants = enchants.where(slot: slot_param) if slot_param.present?

    render json: enchants.map { |record| serialize_enchant(record) }
  end

  private

    def serialize_enchant(record)
      {
        id:          record.id,
        enchantment: {
          id:          record.enchantment.id,
          blizzard_id: record.enchantment.blizzard_id,
          name:        record.enchantment.t("name", locale: locale_param)
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
