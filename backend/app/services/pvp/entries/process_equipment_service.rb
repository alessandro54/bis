module Pvp
  module Entries
    class ProcessEquipmentService < BaseService
      def initialize(entry:, locale: "en_US")
        @entry  = entry
        @locale = locale
      end

      def call
        return success(entry) if entry.equipment_processed_at.present?

        raw_equipment = entry.raw_equipment
        unless raw_equipment.is_a?(Hash) && raw_equipment["equipped_items"].present?
          return failure("Missing equipped_items in raw_equipment")
        end

        equipment_service = Blizzard::Data::Items::UpsertFromRawEquipmentService.new(
          raw_equipment: raw_equipment,
          locale:        locale
        )
        processed_equipment = equipment_service.call

        ActiveRecord::Base.transaction do
          equipment_attrs = {
            equipment_processed_at: Time.zone.now,
            item_level:             equipment_service.item_level,
            raw_equipment:          processed_equipment,
            **equipment_service.tier_set
          }.compact

          entry.update!(equipment_attrs) unless equipment_attrs.empty?

          rebuild_entry_items(processed_equipment)
        end

        success(entry)
      rescue => e
        failure(e)
      end

      private

        attr_reader :entry, :locale

        def rebuild_entry_items(processed_equipment)
          equipped_items =
            if processed_equipment.is_a?(Hash)
              processed_equipment["equipped_items"] || []
            else
              processed_equipment || []
            end

          # Use delete_all instead of destroy_all to skip callbacks (faster)
          entry.pvp_leaderboard_entry_items.delete_all

          # Prepare bulk insert data
          item_records = []
          blizzard_item_ids = equipped_items.filter_map do |equipped|
            next unless equipped.is_a?(Hash)
            equipped.dig("item", "id")
          end.compact

          # Fetch all items in one query
          items_by_blizzard_id = Item.where(blizzard_id: blizzard_item_ids)
                                     .pluck(:blizzard_id, :id)
                                     .to_h

          equipped_items.each do |equipped|
            next unless equipped.is_a?(Hash)

            blizzard_item_id = equipped.dig("item", "id")
            slot_type        = equipped.dig("slot", "type")
            item_level       = equipped.dig("level", "value")
            context          = equipped["context"]

            next unless blizzard_item_id && slot_type

            item_id = items_by_blizzard_id[blizzard_item_id]
            next unless item_id

            item_records << {
              pvp_leaderboard_entry_id: entry.id,
              item_id: item_id,
              slot: slot_type,
              item_level: item_level,
              context: context,
              raw: equipped,
              created_at: Time.current,
              updated_at: Time.current
            }
          end

          # Bulk insert all entry items
          PvpLeaderboardEntryItem.insert_all!(item_records) if item_records.any?
        end
    end
  end
end
