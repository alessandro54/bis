module Pvp
  module Entries
    class ProcessSpecializationService < BaseService
      def initialize(character:, raw_specialization:, locale: "en_US")
        @character          = character
        @raw_specialization = raw_specialization
        @locale             = locale
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      def call
        spec_service = Blizzard::Data::CharacterEquipmentSpecializationsService.new(raw_specialization)

        unless spec_service.has_data?
          return failure("No specialization data")
        end

        active_spec = spec_service.active_specialization
        hero_tree   = spec_service.active_hero_tree
        spec_id     = Wow::Catalog.normalize_spec_id(active_spec["id"])
        class_id    = Wow::Catalog.class_id_for_spec(spec_id)

        unless spec_id && class_id
          return failure("Unknown spec id: #{active_spec["id"].inspect}")
        end

        char_attrs = {}

        # rubocop:disable Rails/SkipsModelValidations
        if spec_service.class_slug.present?
          normalized_slug = spec_service.class_slug.to_s.downcase.strip.gsub(" ", "_")
          if character.class_slug != normalized_slug || character.class_id != class_id
            char_attrs[:class_slug] = normalized_slug
            char_attrs[:class_id]   = class_id
          end
        end

        process_all_specs_talents(spec_service, char_attrs)
        # rubocop:enable Rails/SkipsModelValidations

        # Build per-spec hero tree info for SyncCharacterService
        # to apply to entries that don't match the active spec
        per_spec_hero_trees = spec_service.all_specializations.each_with_object({}) do |s, h|
          sid = Wow::Catalog.normalize_spec_id(s[:spec_id])
          next unless sid

          ht = s[:hero_tree]
          h[sid] = {
            hero_talent_tree_name: ht&.fetch("name", nil).to_s.downcase,
            hero_talent_tree_id:   ht&.fetch("id", nil)
          }
        end

        entry_attrs = {
          specialization_processed_at: Time.zone.now,
          spec_id:                     spec_id,
          hero_talent_tree_name:       hero_tree&.fetch("name", nil).to_s.downcase,
          hero_talent_tree_id:         hero_tree&.fetch("id", nil)
        }

        success(nil, context: {
          entry_attrs:         entry_attrs,
          char_attrs:          char_attrs,
          per_spec_hero_trees: per_spec_hero_trees
        })
      rescue => e
        failure(e)
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      private

        attr_reader :character, :raw_specialization, :locale

        # Process talents for ALL specs returned by the API, not just the active one.
        # Each spec's talents are stored independently, keyed by spec_id.
        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def process_all_specs_talents(spec_service, char_attrs)
          current_codes = character.spec_talent_loadout_codes || {}
          new_codes = current_codes.dup

          spec_service.all_specializations.each do |spec_data|
            sid = Wow::Catalog.normalize_spec_id(spec_data[:spec_id])
            next unless sid

            new_code     = spec_data[:talent_loadout_code]
            current_code = current_codes[sid.to_s]

            next if current_code == new_code

            talent_hash = spec_data[:talents].merge(
              "pvp_talents" => spec_data[:pvp_talents],
              "talent_loadout_code" => new_code
            ).stringify_keys!

            talent_upsert = Blizzard::Data::Talents::UpsertFromRawSpecializationService.call(
              raw_specialization: talent_hash,
              locale:             locale
            )

            rebuild_character_talents(talent_upsert, sid)
            upsert_spec_default_points(talent_upsert, sid)
            new_codes[sid.to_s] = new_code
          end

          char_attrs[:spec_talent_loadout_codes] = new_codes if new_codes != current_codes
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        def upsert_spec_default_points(talent_upsert, spec_id)
          now     = Time.current
          records = []

          talent_upsert.each do |_type, talents|
            Array(talents).each do |td|
              next unless td[:talent_id]

              records << {
                talent_id:      td[:talent_id],
                spec_id:        spec_id,
                default_points: td[:default_points].to_i,
                created_at:     now,
                updated_at:     now
              }
            end
          end

          return if records.empty?

          # rubocop:disable Rails/SkipsModelValidations
          TalentSpecAssignment.upsert_all(
            records.uniq { |r| [ r[:talent_id], r[:spec_id] ] },
            unique_by:   %i[talent_id spec_id],
            update_only: %i[default_points]
          )
          # rubocop:enable Rails/SkipsModelValidations
        end

        def rebuild_character_talents(talent_upsert, spec_id)
          character.character_talents.where(spec_id: spec_id).delete_all

          now     = Time.current
          records = []

          talent_upsert.each do |_type, talents|
            Array(talents).each do |talent_data|
              next unless talent_data[:talent_id]

              records << {
                character_id: character.id,
                talent_id:    talent_data[:talent_id],
                talent_type:  talent_data[:talent_type],
                rank:         talent_data[:rank] || 1,
                slot_number:  talent_data[:slot_number],
                spec_id:      spec_id,
                created_at:   now,
                updated_at:   now
              }
            end
          end

          # rubocop:disable Rails/SkipsModelValidations
          CharacterTalent.insert_all!(records) if records.any?
          # rubocop:enable Rails/SkipsModelValidations
        end
    end
  end
end
