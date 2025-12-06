module Pvp
  module Entries
    class ProcessSpecializationService < ApplicationService
      def initialize(entry:)
        @entry = entry
      end

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
        spec_id     = active_spec["id"]
        class_id    = Wow::Catalog.class_id_for_spec(spec_id)

        ActiveRecord::Base.transaction do
          entry.update!(
            specialization_processed_at: Time.zone.now,
            spec_id:                     spec_id,
            hero_talent_tree_name:       hero_tree["name"].downcase,
            hero_talent_tree_id:         hero_tree["id"],
            raw_specialization:          spec_service.talents
          )

          if spec_service.class_slug.present?
            normalized_slug = spec_service.class_slug.to_s.downcase.strip.gsub(" ", "_")

            entry.character.update!(
              class_slug: normalized_slug,
              class_id:   class_id
            )
          end
        end

        success(entry)
      rescue => e
        failure(e)
      end

      private

        attr_reader :entry
    end
  end
end
