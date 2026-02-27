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

        talent_upsert = Blizzard::Data::Talents::UpsertFromRawSpecializationService.call(
          raw_specialization: spec_service.talents,
          locale:             locale
        )
        new_loadout_code = spec_service.talents["talent_loadout_code"]

        if character.talent_loadout_code != new_loadout_code
          char_attrs[:talent_loadout_code] = new_loadout_code
          rebuild_character_talents(talent_upsert)
        end
        # rubocop:enable Rails/SkipsModelValidations

        entry_attrs = {
          specialization_processed_at: Time.zone.now,
          spec_id:                     spec_id,
          hero_talent_tree_name:       hero_tree&.fetch("name", nil).to_s.downcase,
          hero_talent_tree_id:         hero_tree&.fetch("id", nil)
        }

        success(nil, context: { entry_attrs: entry_attrs, char_attrs: char_attrs })
      rescue => e
        failure(e)
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      private

        attr_reader :character, :raw_specialization, :locale

        def rebuild_character_talents(talent_upsert)
          character.character_talents.delete_all

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
