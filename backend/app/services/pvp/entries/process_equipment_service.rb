module Pvp
  module Entries
    class ProcessEquipmentService < BaseService
      def initialize(entry:, locale: "en_US")
        @entry  = entry
        @locale = locale
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      def call
        # Skip if equipment was recently processed (within configurable TTL)
        # This prevents redundant processing when same entry is queued multiple times
        ttl_hours = ENV.fetch("EQUIPMENT_PROCESS_TTL_HOURS", 1).to_i
        if entry.equipment_processed_at.present? && entry.equipment_processed_at > ttl_hours.hours.ago
          return success(entry)
        end

        raw_equipment = entry.raw_equipment
        unless raw_equipment.is_a?(Hash) && raw_equipment["equipped_items"].present?
          return failure("Missing equipped_items in raw_equipment")
        end

        equipment_service = Blizzard::Data::Items::UpsertFromRawEquipmentService.new(
          raw_equipment: raw_equipment,
          locale:        locale
        )
        processed_equipment = equipment_service.call

        # Build equipment attributes (written by ProcessEntryService in a single UPDATE)
        equipment_attrs = {
          equipment_processed_at: Time.zone.now,
          raw_equipment:          PvpLeaderboardEntry.compress_json_value(processed_equipment)
        }

        equipment_attrs[:item_level] = equipment_service.item_level if equipment_service.item_level.present?
        equipment_attrs.merge!(equipment_service.tier_set) if equipment_service.tier_set.present?

        # Return attrs and a proc for rebuilding items (called inside the shared transaction)
        rebuild_proc = -> { rebuild_entry_items(processed_equipment) }

        success(entry, context: { attrs: equipment_attrs, rebuild_items_proc: rebuild_proc })
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
