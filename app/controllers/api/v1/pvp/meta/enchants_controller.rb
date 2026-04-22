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

      merge_enchant_variants(enchants.map { |record| serialize_enchant(record) })
    end

    render json: json
    set_cache_headers
  end
  # rubocop:enable Metrics/AbcSize

  private

    # Merge rank variants (same name, same slot) into one entry so the frontend
    # doesn't show duplicates. Usage is summed across variants.
    # rubocop:disable Metrics/AbcSize
    def merge_enchant_variants(serialized)
      serialized
        .group_by { |e| [ e[:slot], e[:enchantment][:name] ] }
        .map do |(_slot, _name), group|
          next group.first if group.size == 1

          primary      = group.max_by { |e| e[:usage_pct] }
          merged_pct   = group.sum { |e| e[:usage_pct] }
          any_prev     = group.any? { |e| e[:prev_usage_pct] }
          merged_prev  = any_prev ? group.sum { |e| e[:prev_usage_pct].to_f } : nil
          primary.merge(
            usage_count:    group.sum { |e| e[:usage_count] },
            usage_pct:      merged_pct,
            prev_usage_pct: merged_prev,
            trend:          trend_for(merged_pct, merged_prev)
          )
        end
        .sort_by { |e| -e[:usage_pct] }
    end
    # rubocop:enable Metrics/AbcSize

    def serialize_enchant(record)
      {
        id:             record.id,
        enchantment:    {
          id:          record.enchantment.id,
          blizzard_id: record.enchantment.blizzard_id,
          name:        record.enchantment.t("name", locale: locale_param)
        },
        slot:           record.slot,
        usage_count:    record.usage_count,
        usage_pct:      record.usage_pct.to_f,
        prev_usage_pct: record.prev_usage_pct&.to_f,
        trend:          trend_for(record.usage_pct, record.prev_usage_pct),
        snapshot_at:    record.snapshot_at
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
