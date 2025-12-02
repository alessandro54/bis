module Pvp
  class ProcessLeaderboardEntrySpecializationJob < ApplicationJob
    queue_as :pvp_processing

    def perform(entry_id:, locale: "en_US")
      entry = ::PvpLeaderboardEntry.find(entry_id)

      return if entry.specialization_processed_at.present?

      spec_service = Blizzard::Data::CharacterEquipmentSpecializationsService.new(entry.raw_specialization)
      return unless spec_service.has_data?

      active_spec = spec_service.active_specialization
      hero_tree = spec_service.active_hero_tree
      spec_id = active_spec["id"]
      class_id = Wow::Catalog.class_id_for_spec(spec_id)

      Rails.logger.silence do
        entry.update!(
          specialization_processed_at: Time.zone.now,
          spec_id:                     spec_id,
          hero_talent_tree_name:       hero_tree["name"].downcase,
          hero_talent_tree_id:         hero_tree["id"],
          raw_specialization:          spec_service.talents
        )
      end

      return unless spec_service.class_slug.present?

      normalized_slug = spec_service.class_slug.to_s.downcase.strip.gsub(" ", "_")
      entry.character.update!(
        class_slug: normalized_slug,
        class_id:   class_id
      )
    end
  end
end
