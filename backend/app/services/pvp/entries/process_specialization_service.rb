module Pvp
  module Entries
    class ProcessSpecializationService < ApplicationService
      def initialize(entry:)
        @entry = entry
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

        success(entry, context: { attrs: spec_attrs })
      rescue => e
        failure(e)
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      private

        attr_reader :entry
    end
  end
end
