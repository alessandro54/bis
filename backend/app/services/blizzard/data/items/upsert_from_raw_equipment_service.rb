module Blizzard
  module Data
    module Items
      class UpsertFromRawEquipmentService
        EXCLUDED_SLOTS = %w[TABARD SHIRT].freeze

        def call
          return if items.empty?

          # Bulk upsert all items at once for better performance
          item_records = items.filter_map do |raw_item|
            build_item_record(raw_item)
          end

          return if item_records.empty?

          # Upsert items in bulk
          Item.upsert_all(
            item_records,
            unique_by: :blizzard_id,
            returning: false
          )

          # Handle translations separately (translations are localized and may vary)
          # Reuse blizzard_ids from item_records to avoid re-extraction
          blizzard_ids = item_records.map { |record| record[:blizzard_id] }
          upsert_translations(blizzard_ids)
        end

        def self.call(raw_equipment:, locale: "en_US")
          new(raw_equipment:, locale:).call
        end

        def initialize(raw_equipment:, locale: "en_US")
          @items = valid_items(raw_equipment)
          @locale = locale
        end


        def valid_items(raw_equipment)
          Array(raw_equipment["equipped_items"]).select { |item| valid_item?(item) }
        end

        def valid_item?(raw_item)
          slot_type = raw_item.dig("slot", "type")
          item_level = raw_item.dig("level", "value")

          !EXCLUDED_SLOTS.include?(slot_type) && item_level.to_i > 0
        end

        def item_level
          items.map { |i| i.dig("level", "value") }.compact.sum / items.size
        end

        def tier_set
          block = items.map { |i| i["set"] }.compact.first
          return unless block

          effects = block["effects"] || []

          {
            tier_set_id:     block.dig("item_set", "id"),
            tier_set_name:   block.dig("item_set", "name"),
            tier_set_pieces: (block["items"] || []).count { |x| x["is_equipped"] },
            tier_4p_active:  effects.any? { |eff| eff["required_count"] == 4 && eff["is_active"] }
          }
        end

        private

          attr_reader :items, :locale

          def extract_blizzard_id(raw_item)
            raw_item.dig("item", "id")
          end

          def build_item_record(raw_item)
            blizzard_id = extract_blizzard_id(raw_item)
            return nil unless blizzard_id

            {
              blizzard_id:       blizzard_id,
              inventory_type:    raw_item.dig("inventory_type", "type")&.downcase,
              item_class:        raw_item.dig("item_class", "name")&.downcase,
              item_subclass:     raw_item.dig("item_subclass", "name")&.downcase,
              blizzard_media_id: raw_item.dig("media", "id"),
              quality:           raw_item.dig("quality", "type")&.downcase
            }
          end

          def upsert_translations(blizzard_ids)
            # Batch fetch items that need translations
            return if blizzard_ids.empty?

            items_by_blizzard_id = Item.where(blizzard_id: blizzard_ids).index_by(&:blizzard_id)

            items.each do |raw_item|
              blizzard_id = extract_blizzard_id(raw_item)
              name = raw_item.dig("name")

              next unless blizzard_id && name.present?

              item = items_by_blizzard_id[blizzard_id]
              next unless item

              item.set_translation("name", locale, name)
            end
          end
      end
    end
  end
end
