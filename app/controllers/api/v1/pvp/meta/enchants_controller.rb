class Api::V1::Pvp::Meta::EnchantsController < Api::V1::BaseController
  before_action :validate_params!

  # rubocop:disable Metrics/AbcSize
  def index
    cache_key = meta_cache_key("enchants", bracket_param, spec_id_param, slot_param, locale_param)

    json = meta_cache_fetch(cache_key) do
      season = meta_season_for(PvpMetaEnchantPopularity)
      enchants = PvpMetaEnchantPopularity
        .includes(enchantment: :translations)
        .where(pvp_season: season)
        .where(bracket: bracket_param)
        .where(spec_id: spec_id_param)
        .order(usage_pct: :desc)

      enchants = enchants.where(slot: slot_param) if slot_param.present?

      enchants.map { |record| serialize_enchant(record) }
    end

    render json: json
    set_cache_headers
  end
  # rubocop:enable Metrics/AbcSize

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

    def slot_param
      @slot_param ||= validate_slot(params[:slot])
    end
end
