module Blizzard
  module Data
    module Items
      class UpsertFromRawEquipmentService
        EXCLUDED_SLOTS = %w[TABARD SHIRT].freeze
        ITEM_CACHE_TTL = 1.hour

        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def call
          return { "equipped_items" => {} } if items.empty?

          item_records = items.filter_map { |raw_item| build_item_record(raw_item) }
          return { "equipped_items" => {} } if item_records.empty?

          # Enchantment source items (scrolls/reagents) are referenced by FK in
          # character_items but are NOT part of the equipped_items list, so they must
          # be upserted separately before the FK insert happens.
          enchantment_source_records = items.filter_map do |raw_item|
            blz_id = extract_enchantment_source_blizzard_id(raw_item)
            blz_id ? { blizzard_id: blz_id } : nil
          end

          all_records = (item_records + enchantment_source_records).uniq { |r| r[:blizzard_id] }

          # rubocop:disable Rails/SkipsModelValidations
          Item.upsert_all(all_records, unique_by: :blizzard_id, returning: false)
          # rubocop:enable Rails/SkipsModelValidations

          all_blizzard_ids = all_records.map { |r| r[:blizzard_id] }
          items_by_blizzard_id = fetch_item_ids_with_cache(all_blizzard_ids)

          # Translations only for equipped items — enchantment sources have no name in raw data
          upsert_translations(items_by_blizzard_id)

          # Build slot -> item mapping with all relevant data
          equipped_items = {}
          items.each do |raw_item|
            slot = raw_item.dig("slot", "type")&.downcase
            blizzard_id = extract_blizzard_id(raw_item)
            next unless slot && blizzard_id

            enc_src_blz_id = extract_enchantment_source_blizzard_id(raw_item)

            equipped_items[slot] = {
              "blizzard_id"                => blizzard_id,
              "item_id"                    => items_by_blizzard_id[blizzard_id],
              "item_level"                 => raw_item.dig("level", "value"),
              "name"                       => raw_item["name"],
              "quality"                    => raw_item.dig("quality", "type")&.downcase,
              "context"                    => raw_item["context"],
              "bonus_list"                 => raw_item["bonus_list"] || [],
              "enchantment_id"             => extract_enchantment_id(raw_item),
              "enchantment_source_item_id" => enc_src_blz_id ? items_by_blizzard_id[enc_src_blz_id] : nil,
              "embellishment_spell_id"     => extract_embellishment_spell_id(raw_item),
              "sockets"                    => extract_sockets(raw_item)
            }
          end

          { "equipped_items" => equipped_items }
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

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
          levels = items.map { |i| i.dig("level", "value") }.compact
          return if levels.empty?

          levels.sum / levels.size
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

          # Fetch item IDs with caching to reduce DB queries
          # Items rarely change, so we can cache the blizzard_id -> id mapping
          # rubocop:disable Metrics/AbcSize
          def fetch_item_ids_with_cache(blizzard_ids)
            return {} if blizzard_ids.empty?

            # Single round-trip to cache store instead of N individual reads
            cache_keys = blizzard_ids.index_with { |blz_id| "item:blz:#{blz_id}" }
            cached = Rails.cache.read_multi(*cache_keys.values)

            result = {}
            uncached_ids = []

            blizzard_ids.each do |blz_id|
              cached_value = cached[cache_keys[blz_id]]
              if cached_value
                result[blz_id] = cached_value
              else
                uncached_ids << blz_id
              end
            end

            # Fetch uncached from DB and populate cache
            if uncached_ids.any?
              Item.where(blizzard_id: uncached_ids).pluck(:blizzard_id, :id).each do |blz_id, id|
                result[blz_id] = id
                Rails.cache.write("item:blz:#{blz_id}", id, expires_in: ITEM_CACHE_TTL)
              end
            end

            result
          end
          # rubocop:enable Metrics/AbcSize

          def extract_blizzard_id(raw_item)
            raw_item.dig("item", "id")
          end

          def extract_enchantment_id(raw_item)
            permanent = Array(raw_item["enchantments"])
              .find { |e| e.dig("enchantment_slot", "type") == "PERMANENT" }
            permanent&.dig("enchantment_id")
          end

          # Returns the Blizzard ID of the enchanting reagent/scroll, not an internal item ID.
          def extract_enchantment_source_blizzard_id(raw_item)
            permanent = Array(raw_item["enchantments"])
              .find { |e| e.dig("enchantment_slot", "type") == "PERMANENT" }
            permanent&.dig("source_item", "id")
          end

          def extract_embellishment_spell_id(raw_item)
            Array(raw_item["spells"]).first&.dig("spell", "id")
          end

          def extract_sockets(raw_item)
            Array(raw_item["sockets"]).map do |socket|
              {
                "type"    => socket.dig("socket_type", "type"),
                "item_id" => socket.dig("item", "id")
              }
            end
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

          # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          def upsert_translations(items_by_blizzard_id)
            return if items_by_blizzard_id.empty?

            now = Time.current

            translation_records = items.filter_map do |raw_item|
              blizzard_id = extract_blizzard_id(raw_item)
              name = raw_item.dig("name")
              item_id = items_by_blizzard_id[blizzard_id]

              next unless blizzard_id && name.present? && item_id

              {
                translatable_type: "Item",
                translatable_id:   item_id,
                key:               "name",
                locale:            locale,
                value:             name,
                meta:              { source: "blizzard" },
                created_at:        now,
                updated_at:        now
              }
            end

            return if translation_records.empty?

            # Deduplicate by unique constraint columns to avoid CardinalityViolation
            unique_records = translation_records.uniq do |r|
              [ r[:translatable_type], r[:translatable_id], r[:locale], r[:key] ]
            end

            # Bulk upsert all translations in one query instead of N individual saves
            # rubocop:disable Rails/SkipsModelValidations
            Translation.upsert_all(
              unique_records,
              unique_by: %i[translatable_type translatable_id locale key]
            )
            # rubocop:enable Rails/SkipsModelValidations
          end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      end
    end
  end
end
