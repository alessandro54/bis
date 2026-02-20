module Pvp
  module Entries
    class ProcessEquipmentService < BaseService
      EXCLUDED_SLOTS = %w[TABARD SHIRT].freeze

      def initialize(character:, raw_equipment:, locale: "en_US")
        @character     = character
        @raw_equipment = raw_equipment
        @locale        = locale
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      def call
        unless raw_equipment.is_a?(Hash) && raw_equipment["equipped_items"].present?
          return failure("Missing equipped_items in raw_equipment")
        end

        # Compute fingerprint from raw Blizzard IDs + item level + enchantment —
        # no DB round-trip required. Skip all DB writes when gear is unchanged.
        new_fingerprint = raw_fingerprint

        if character.equipment_fingerprint == new_fingerprint
          return success(nil, context: { entry_attrs: { equipment_processed_at: Time.zone.now } })
        end

        equipment_service = Blizzard::Data::Items::UpsertFromRawEquipmentService.new(
          raw_equipment: raw_equipment,
          locale:        locale
        )
        processed = equipment_service.call

        rebuild_character_items(character, processed, new_fingerprint)

        entry_attrs = { equipment_processed_at: Time.zone.now }
        entry_attrs[:item_level] = equipment_service.item_level if equipment_service.item_level.present?
        entry_attrs.merge!(equipment_service.tier_set) if equipment_service.tier_set.present?

        success(nil, context: { entry_attrs: entry_attrs })
      rescue => e
        failure(e)
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      private

        attr_reader :character, :raw_equipment, :locale

        # Fingerprint built entirely from raw API data — slot, Blizzard item ID,
        # item level, and permanent enchantment ID. No DB lookups needed, so the
        # check happens before any writes.
        def raw_fingerprint
          Array(raw_equipment["equipped_items"])
            .reject { |item|
              slot  = item.dig("slot", "type")
              ilvl  = item.dig("level", "value").to_i
              EXCLUDED_SLOTS.include?(slot) || ilvl <= 0
            }
            .map { |item|
              slot   = item.dig("slot", "type")&.downcase
              blz_id = item.dig("item", "id")
              ilvl   = item.dig("level", "value").to_i
              enc    = Array(item["enchantments"])
                         .find { |e| e.dig("enchantment_slot", "type") == "PERMANENT" }
                         &.dig("enchantment_id")
              "#{slot}:#{blz_id}:#{ilvl}:#{enc}"
            }
            .sort
            .join(",")
        end

        # rubocop:disable Metrics/MethodLength
        def rebuild_character_items(character, processed, new_fingerprint)
          equipped_items = processed.is_a?(Hash) ? processed["equipped_items"] : {}

          character.character_items.delete_all

          now = Time.current
          records = equipped_items.filter_map do |slot, item_data|
            next unless item_data.is_a?(Hash) && item_data["item_id"]

            {
              character_id:               character.id,
              item_id:                    item_data["item_id"],
              slot:                       slot.upcase,
              item_level:                 item_data["item_level"],
              context:                    item_data["context"],
              enchantment_id:             item_data["enchantment_id"],
              enchantment_source_item_id: item_data["enchantment_source_item_id"],
              embellishment_spell_id:     item_data["embellishment_spell_id"],
              bonus_list:                 item_data["bonus_list"] || [],
              sockets:                    item_data["sockets"] || [],
              created_at:                 now,
              updated_at:                 now
            }
          end

          # rubocop:disable Rails/SkipsModelValidations
          CharacterItem.insert_all!(records) if records.any?
          character.update_columns(equipment_fingerprint: new_fingerprint)
          # rubocop:enable Rails/SkipsModelValidations
        end
      # rubocop:enable Metrics/MethodLength
    end
  end
end
