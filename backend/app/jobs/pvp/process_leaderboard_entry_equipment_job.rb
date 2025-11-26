module Pvp
  class ProcessLeaderboardEntryEquipmentJob < ApplicationJob
    queue_as :pvp_processing

    def perform(entry_id:, locale: "en_US")
      entry = ::PvpLeaderboardEntry.find(entry_id)
      raw_equipment = entry.raw_equipment

      return if entry.equipment_processed_at.present?
      return unless raw_equipment.is_a?(Hash) && raw_equipment["equipped_items"].present?

      equipment_service = Blizzard::Data::Items::UpsertFromRawEquipmentService.new(
        raw_equipment: raw_equipment,
        locale:        locale
      )

      processed_equipment = equipment_service.call

      Rails.logger.silence do
        ActiveRecord::Base.transaction do
          entry.update!(
            equipment_processed_at: Time.zone.now,
            item_level:             equipment_service.item_level,
            raw_equipment:          processed_equipment,
            **equipment_service.tier_set
          )

          rebuild_entry_items(entry, processed_equipment)
        end
      end
    end

    def rebuild_entry_items(entry, processed_equipment)
      equipped_items = processed_equipment || []

      entry.pvp_leaderboard_entry_items.destroy_all

      equipped_items.each do |equipped|
        blizzard_item_id = equipped.dig("item", "id")
        slot_type        = equipped.dig("slot", "type")
        item_level       = equipped.dig("level", "value")
        context          = equipped["context"] # if present in your JSON

        next unless blizzard_item_id && slot_type

        item = Item.find_by(blizzard_id: blizzard_item_id)
        next unless item

        entry.pvp_leaderboard_entry_items.create!(
          item:       item,
          slot:       slot_type,
          item_level: item_level,
          context:    context,
          raw:        equipped
        )
      end
    end
  end
end
