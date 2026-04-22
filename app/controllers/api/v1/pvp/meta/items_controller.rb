class Api::V1::Pvp::Meta::ItemsController < Api::V1::BaseController
  before_action :validate_params!

  # rubocop:disable Metrics/AbcSize
  def index
    cache_key = meta_cache_key("items", bracket_param, spec_id_param, slot_param, locale_param)

    json = meta_cache_fetch(cache_key) do
      season = meta_season_for(PvpMetaItemPopularity)
      items  = PvpMetaItemPopularity.for_meta(season:, bracket: bracket_param, spec_id: spec_id_param)
      items  = items.where(slot: slot_param) if slot_param.present?

      crafting_map = Pvp::Meta::CraftingStatsQuery.new(
        items.map(&:item_id), season:, bracket: bracket_param, spec_id: spec_id_param
      ).call

      items.map do |r|
        Pvp::Meta::ItemSerializer.new(r, locale: locale_param, crafting_stats: crafting_map[r.item_id]).call
      end
    end

    render json: json
    set_cache_headers
    enqueue_unsynced_items
  end
  # rubocop:enable Metrics/AbcSize

  private

    def validate_params!
      validate_bracket!(params.require(:bracket)) or return
      validate_spec_id!(params.require(:spec_id)) or return
    end

    def bracket_param = @bracket_param ||= params.require(:bracket)
    def spec_id_param = @spec_id_param ||= params.require(:spec_id).to_i
    def slot_param    = @slot_param    ||= validate_slot(params[:slot])

    def enqueue_unsynced_items
      items = PvpMetaItemPopularity
        .includes(:item)
        .where(pvp_season: meta_season_for(PvpMetaItemPopularity), bracket: bracket_param, spec_id: spec_id_param)
      unsynced_ids = items.map(&:item).reject(&:meta_synced?).map(&:id)
      Items::SyncItemMetaBatchJob.perform_later(item_ids: unsynced_ids) if unsynced_ids.any?
    end
end
