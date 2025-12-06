module Blizzard
  module Data
    module Items
      class UpsertFromRawEquipmentService
        EXCLUDED_SLOTS = %w[TABARD SHIRT].freeze

        def call
          items.each do |raw_item|
            upsert_item(raw_item)
          end
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

          def upsert_item(raw_item)
            blizzard_id = raw_item.dig("item", "id")

            return unless blizzard_id

            item = Item.find_or_initialize_by(blizzard_id:)

            item.assign_attributes(
              inventory_type:    raw_item.dig("inventory_type", "type")&.downcase,
              item_class:        raw_item.dig("item_class", "name")&.downcase,
              item_subclass:     raw_item.dig("item_subclass", "name")&.downcase,
              blizzard_media_id: raw_item.dig("media", "id"),
              quality:           raw_item.dig("quality", "type")&.downcase
            )

            item.save!

            name = raw_item.dig("name")

            item.set_translation("name", locale, name) if name.present?
          end
      end
    end
  end
end
