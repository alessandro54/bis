module Pvp
  class ProcessLeaderboardEntryJob < ApplicationJob
    queue_as :pvp_processing

    def perform(entry_id:, locale: "en_US")
      entry = ::PvpLeaderboardEntry.find_by(id: entry_id)
      return unless entry

      process_equipment(entry, locale:)
      process_specialization(entry)
    end

    private
      def process_equipment(entry, locale: "en_US")
        return if entry.equipment_processed_at.present?

        raw_equipment = entry.raw_equipment
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
          context          = equipped["context"]

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

      def process_specialization(entry)
        spec_service = Blizzard::Data::CharacterEquipmentSpecializationsService.new(entry.raw_specialization)
        return unless spec_service.has_data?

        active_spec = spec_service.active_specialization
        hero_tree = spec_service.active_hero_tree
        spec_id = active_spec["id"]
        class_id = Wow::Catalog.class_id_for_spec(spec_id)

        Rails.logger.silence do
          entry.update!(
            specialization_processed_at: Time.zone.now,
            spec_id:                     spec_id,
            hero_talent_tree_name:       hero_tree["name"].downcase,
            hero_talent_tree_id:         hero_tree["id"],
            raw_specialization:          spec_service.talents
          )
        end

        return unless spec_service.class_slug.present?

        normalized_slug = spec_service.class_slug.to_s.downcase.strip.gsub(" ", "_")
        entry.character.update!(
          class_slug: normalized_slug,
          class_id:   class_id
        )
      end
  end
end
