class Api::V1::Pvp::Meta::ItemsController < Api::V1::BaseController
  def index
    items = PvpMetaItemPopularity
      .includes(item: :translations)
      .where(pvp_season: current_season)
      .where(bracket: bracket_param)
      .where(spec_id: spec_id_param)
      .order(usage_pct: :desc)

    items = items.where(slot: slot_param) if slot_param.present?

    item_ids = items.map(&:item_id)
    crafting_map = crafting_stats_for(item_ids)

    render json: items.map { |record| serialize_item(record, crafting_map) }

    unsynced_ids = items.map(&:item).reject(&:meta_synced?).map(&:id)
    Items::SyncItemMetaBatchJob.perform_later(item_ids: unsynced_ids) if unsynced_ids.any?
  end

  private

    def serialize_item(record, crafting_map)
      stats = crafting_map[record.item_id]
      {
        id:                 record.id,
        item:               {
          id:          record.item.id,
          blizzard_id: record.item.blizzard_id,
          name:        record.item.t("name", locale: locale_param),
          icon_url:    record.item.icon_url,
          quality:     record.item.quality
        },
        slot:               record.slot,
        usage_count:        record.usage_count,
        usage_pct:          record.usage_pct.to_f,
        snapshot_at:        record.snapshot_at,
        crafted:            stats.present?,
        top_crafting_stats: stats || []
      }
    end

    # Returns a map of item_id => most popular crafting_stats array for crafted items only.
    def crafting_stats_for(item_ids)
      return {} if item_ids.empty?

      rows = CharacterItem
        .joins(character: { pvp_leaderboard_entries: :pvp_leaderboard })
        .where(pvp_leaderboards: { bracket: bracket_param, pvp_season: current_season })
        .where(pvp_leaderboard_entries: { spec_id: spec_id_param })
        .where(item_id: item_ids)
        .where("crafting_stats <> '{}'")
        .group(:item_id, :crafting_stats)
        .order(Arel.sql("COUNT(*) DESC"))
        .pluck(:item_id, :crafting_stats)

      result = {}
      rows.each do |item_id, stats|
        result[item_id] ||= stats  # first row per item_id is the most popular (ORDER BY COUNT DESC)
      end
      result
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
