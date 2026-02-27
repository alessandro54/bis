module Blizzard
  module Data
    module Talents
      class UpsertFromRawSpecializationService
        TALENT_CACHE_TTL = 1.hour

        def self.call(raw_specialization:, locale: "en_US")
          new(raw_specialization:, locale:).call
        end

        def initialize(raw_specialization:, locale: "en_US")
          @raw_specialization = raw_specialization
          @locale = locale
        end

        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def call
          return empty_result unless raw_specialization.is_a?(Hash)

          talent_records = []
          junction_data  = {}

          # Extract class/spec/hero talents (all share the same structure)
          %w[class spec hero].each do |type|
            talents = Array(raw_specialization["#{type}_talents"])
            type_records = []

            talents.each do |talent|
              blizzard_id = talent[:id] || talent["id"]
              next unless blizzard_id

              talent_records << {
                blizzard_id: blizzard_id,
                name:        talent[:name] || talent["name"],
                talent_type: type,
                spell_id:    nil
              }

              rank = talent[:rank] || talent["rank"] || 1
              type_records << { blizzard_id: blizzard_id, rank: rank }
            end

            junction_data[type] = type_records
          end

          # Extract PVP talents (different structure — has spell_tooltip)
          pvp_talents = Array(raw_specialization["pvp_talents"])
          pvp_records = []

          pvp_talents.each_with_index do |pvp_slot, index|
            selected = pvp_slot.is_a?(Hash) ? (pvp_slot["selected"] || pvp_slot) : nil
            next unless selected

            talent_info = selected.dig("talent") || selected
            blizzard_id = talent_info["id"]
            next unless blizzard_id

            talent_records << {
              blizzard_id: blizzard_id,
              name:        talent_info["name"],
              talent_type: "pvp",
              spell_id:    selected.dig("spell_tooltip", "spell", "id")
            }

            pvp_records << { blizzard_id: blizzard_id, rank: 1, slot_number: index + 2 }
          end

          junction_data["pvp"] = pvp_records

          return empty_result if talent_records.empty?

          # Deduplicate by blizzard_id
          unique_records = talent_records.uniq { |r| r[:blizzard_id] }

          # Bulk upsert talent entities (name lives in translations, not in the talents table)
          # rubocop:disable Rails/SkipsModelValidations
          Talent.upsert_all(
            unique_records.map { |r| r.except(:name) },
            unique_by: :blizzard_id,
            returning: false
          )
          # rubocop:enable Rails/SkipsModelValidations

          # Fetch internal IDs with caching
          blizzard_ids = unique_records.map { |r| r[:blizzard_id] }
          talents_by_blizzard_id = fetch_talent_ids_with_cache(blizzard_ids)

          # Upsert translations
          upsert_translations(unique_records, talents_by_blizzard_id)

          # Build resolved junction data with internal talent_ids
          resolved = {}
          junction_data.each do |type, records|
            resolved[type] = records.filter_map do |rec|
              talent_id = talents_by_blizzard_id[rec[:blizzard_id]]
              next unless talent_id

              {
                talent_id:   talent_id,
                talent_type: type,
                rank:        rec[:rank],
                slot_number: rec[:slot_number]
              }
            end
          end

          resolved
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        private

          attr_reader :raw_specialization, :locale

          def empty_result
            { "class" => [], "spec" => [], "hero" => [], "pvp" => [] }
          end

          # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
          def fetch_talent_ids_with_cache(blizzard_ids)
            return {} if blizzard_ids.empty?

            cache_keys = blizzard_ids.index_with { |blz_id| "talent:blz:#{blz_id}" }
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

            if uncached_ids.any?
              db_rows = Talent.where(blizzard_id: uncached_ids).pluck(:blizzard_id, :id).to_h
              result.merge!(db_rows)
              Rails.cache.write_multi(
                db_rows.transform_keys { |blz_id| "talent:blz:#{blz_id}" },
                expires_in: TALENT_CACHE_TTL
              )
            end

            result
          end
          # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

          # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          def upsert_translations(unique_records, talents_by_blizzard_id)
            return if talents_by_blizzard_id.empty?

            now = Time.current

            translation_records = unique_records.filter_map do |record|
              talent_id = talents_by_blizzard_id[record[:blizzard_id]]
              name = record[:name]
              next unless talent_id && name.present?

              {
                translatable_type: "Talent",
                translatable_id:   talent_id,
                key:               "name",
                locale:            locale,
                value:             name,
                meta:              { source: "blizzard" },
                created_at:        now,
                updated_at:        now
              }
            end

            return if translation_records.empty?

            unique_translations = translation_records.uniq do |r|
              [ r[:translatable_type], r[:translatable_id], r[:locale], r[:key] ]
            end

            # rubocop:disable Rails/SkipsModelValidations
            Translation.upsert_all(
              unique_translations,
              unique_by: %i[translatable_type translatable_id locale key]
            )
            # rubocop:enable Rails/SkipsModelValidations
          end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
      end
    end
  end
end
