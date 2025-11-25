module Pvp
  class ProcessLeaderboardEntryEquipmentJob < ApplicationJob
    queue_as :default

    def perform(entry_id:, locale: "en_US")
      entry = ::PvpLeaderboardEntry.find(entry_id)
      raw_equipment = entry.raw_equipment

      return if entry.equipment_processed_at.present?
      return unless raw_equipment.is_a?(Hash) && raw_equipment["equipped_items"].present?

      equipment_service = Blizzard::Data::Items::UpsertFromRawEquipmentService.new(
        raw_equipment: raw_equipment,
        locale:        locale
      )

      Rails.logger.silence do
        entry.update!(
          equipment_processed_at: Time.zone.now,
          item_level:             equipment_service.item_level,
          raw_equipment:          equipment_service.call,
          **equipment_service.tier_set
        )
      end
    end
  end
end
