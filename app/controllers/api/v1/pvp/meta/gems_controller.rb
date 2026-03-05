class Api::V1::Pvp::Meta::GemsController < Api::V1::BaseController
  # rubocop:disable Metrics/AbcSize
  def index
    cache_key = meta_cache_key("gems", bracket_param, spec_id_param, slot_param, socket_type_param, locale_param)

    json = Rails.cache.fetch(cache_key, expires_in: META_CACHE_TTL) do
      gems = PvpMetaGemPopularity
        .includes(item: :translations)
        .where(pvp_season: current_season)
        .where(bracket: bracket_param)
        .where(spec_id: spec_id_param)
        .order(usage_pct: :desc)

      gems = gems.where(slot: slot_param) if slot_param.present?
      gems = gems.where(socket_type: socket_type_param) if socket_type_param.present?

      gems.map { |record| serialize_gem(record) }
    end

    render json: json
    set_cache_headers
  end
  # rubocop:enable Metrics/AbcSize

  private

    def serialize_gem(record)
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
        socket_type: record.socket_type,
        usage_count: record.usage_count,
        usage_pct:   record.usage_pct.to_f,
        snapshot_at: record.snapshot_at
      }
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

    def socket_type_param
      params[:socket_type]
    end

    def locale_param
      params[:locale] || "en_US"
    end
end
