module Pvp
  module Entries
    class ProcessEquipmentService < BaseService
      def initialize(entry:, locale: "en_US")
        @entry  = entry
        @locale = locale
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
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
          # Always update equipment_processed_at and raw_equipment
          equipment_attrs = {
            equipment_processed_at: Time.zone.now,
            raw_equipment:          processed_equipment
          }

          # Add optional fields if they exist
          equipment_attrs[:item_level] = equipment_service.item_level if equipment_service.item_level.present?
          equipment_attrs.merge!(equipment_service.tier_set) if equipment_service.tier_set.present?

          entry.update!(equipment_attrs)
          rebuild_entry_items(processed_equipment)
        end

        success(entry)
      rescue => e
        failure(e)
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      private

        attr_reader :entry, :locale

        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        def rebuild_entry_items(processed_equipment)
          equipped_items = processed_equipment.is_a?(Hash) ? processed_equipment["equipped_items"] : {}

          # Use delete_all instead of destroy_all to skip callbacks (faster)
          entry.pvp_leaderboard_entry_items.delete_all

          return if equipped_items.empty?

          # Build item records from the slot -> item hash
          item_records = []
          now = Time.current

          equipped_items.each do |slot, item_data|
            next unless item_data.is_a?(Hash)

            item_id = item_data["item_id"]
            next unless item_id

            item_records << {
              pvp_leaderboard_entry_id: entry.id,
              item_id:                  item_id,
              slot:                     slot.upcase,
              item_level:               item_data["item_level"],
              context:                  item_data["context"],
              raw:                      item_data,
              created_at:               now,
              updated_at:               now
            }
          end

          # Bulk insert all entry items
          # rubocop:disable Rails/SkipsModelValidations
          PvpLeaderboardEntryItem.insert_all!(item_records) if item_records.any?
          # rubocop:enable Rails/SkipsModelValidations
        end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
    end
  end
end
