module Pvp
  class LeaderboardEntryProcessEquipmentJob < ApplicationJob
    queue_as :default

    def perform(entry_id:, locale: "en_US")
      entry = ::PvpLeaderboardEntry.find(entry_id)
      raw_equipment = entry.raw_equipment

      return unless raw_equipment.is_a?(Hash)
      return unless raw_equipment.key?("equipped_items")

      equipment_service = Blizzard::Data::Items::UpsertFromRawEquipmentService.new(
        raw_equipment: raw_equipment,
        locale:        locale
      )

      entry.update!(
        item_level:    equipment_service.item_level,
        raw_equipment: equipment_service.call,
        **equipment_service.tier_set
      )
    end
  end
end