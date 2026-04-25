class Api::V1::Pvp::Meta::ItemsController < Api::V1::BaseController
  before_action :validate_params!

  def index
    cache_key = meta_cache_key("items", bracket_param, spec_id_param, slot_param, locale_param)
    json = meta_cache_fetch(cache_key) { serialize_items_response }
    render json: json
    set_cache_headers
    enqueue_unsynced_items
  end

  private

    def validate_params!
      validate_bracket!(params.require(:bracket)) or return
      validate_spec_id!(params.require(:spec_id)) or return
    end

    def bracket_param = @bracket_param ||= params.require(:bracket)
    def spec_id_param = @spec_id_param ||= params.require(:spec_id).to_i
    def slot_param    = @slot_param    ||= validate_slot(params[:slot])

    def serialize_items_response
      season       = meta_season_for(PvpMetaItemPopularity)
      items        = filtered_items(season)
      crafting_map = Pvp::Meta::CraftingStatsQuery.new(
        items.map(&:item_id), season:, bracket: bracket_param, spec_id: spec_id_param
      ).call
      serialized = items.map { |r| Pvp::Meta::ItemSerializer.new(r, locale: locale_param, crafting_stats: crafting_map[r.item_id]).call }
      {
        meta:  { snapshot_at: items.first&.snapshot_at },
        items: serialized
      }
    end

    def filtered_items(season)
      scope = PvpMetaItemPopularity.for_meta(season:, bracket: bracket_param, spec_id: spec_id_param)
      slot_param.present? ? scope.where(slot: slot_param) : scope
    end

    def enqueue_unsynced_items
      items = PvpMetaItemPopularity
        .includes(:item)
        .where(pvp_season: meta_season_for(PvpMetaItemPopularity), bracket: bracket_param, spec_id: spec_id_param)
      unsynced_ids = items.map(&:item).reject(&:meta_synced?).map(&:id)
      Items::SyncItemMetaBatchJob.perform_later(item_ids: unsynced_ids) if unsynced_ids.any?
    end
end
