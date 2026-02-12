module Pvp
  module Entries
    class ProcessSpecializationService < ApplicationService
      def initialize(entry:, locale: "en_US")
        @entry  = entry
        @locale = locale
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      def call
        return success(entry) if entry.specialization_processed_at.present?

        spec_service = Blizzard::Data::CharacterEquipmentSpecializationsService.new(
          entry.raw_specialization
        )

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

        # Build attrs (written by ProcessEntryService in a single UPDATE)
        spec_attrs = {
          specialization_processed_at: Time.zone.now,
          spec_id:                     spec_id,
          hero_talent_tree_name:       hero_tree&.fetch("name", nil).to_s.downcase,
          hero_talent_tree_id:         hero_tree&.fetch("id", nil),
          raw_specialization:          PvpLeaderboardEntry.compress_json_value(spec_service.talents)
        }

        # Update character class info if missing or changed
        # rubocop:disable Rails/SkipsModelValidations
        if spec_service.class_slug.present?
          normalized_slug = spec_service.class_slug.to_s.downcase.strip.gsub(" ", "_")
          character = entry.character

          if character.class_slug != normalized_slug || character.class_id != class_id
            character.update_columns(
              class_slug: normalized_slug,
              class_id:   class_id
            )
          end
        end
        # rubocop:enable Rails/SkipsModelValidations

        # Upsert talent entities (always — cheap idempotent upsert)
        talent_upsert = Blizzard::Data::Talents::UpsertFromRawSpecializationService.call(
          raw_specialization: spec_service.talents,
          locale:             locale
        )

        # Only rebuild character junction records if the build actually changed
        new_loadout_code = spec_service.talents["talent_loadout_code"]
        character = entry.character
        talents_changed = character.talent_loadout_code != new_loadout_code

        rebuild_proc = if talents_changed
          -> {
            # rubocop:disable Rails/SkipsModelValidations
            character.update_columns(talent_loadout_code: new_loadout_code)
            # rubocop:enable Rails/SkipsModelValidations
            rebuild_character_talents(character, talent_upsert)
          }
        end

        success(entry, context: { attrs: spec_attrs, rebuild_talents_proc: rebuild_proc })
      rescue => e
        failure(e)
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      private

        attr_reader :entry, :locale

        def rebuild_character_talents(character, talent_upsert)
          character.character_talents.delete_all

          records = []
          now = Time.current

          talent_upsert.each do |_type, talents|
            Array(talents).each do |talent_data|
              next unless talent_data[:talent_id]

              records << {
                character_id: character.id,
                talent_id:    talent_data[:talent_id],
                talent_type:  talent_data[:talent_type],
                rank:         talent_data[:rank] || 1,
                slot_number:  talent_data[:slot_number],
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
