module Pvp
  class ProcessLeaderboardEntrySpecializationJob < ApplicationJob
    queue_as :default

    def perform(entry_id:, locale: "en_US")
      entry = ::PvpLeaderboardEntry.find(entry_id)
      raw_specialization = entry.raw_specialization

      return if entry.specialization_processed_at.present?

      spec_service = Blizzard::Data::CharacterEquipmentSpecializationsService.new(raw_specialization)
      return unless spec_service.has_data?

      Rails.logger.silence do
        entry.update!(
          specialization_processed_at: Time.zone.now,
          spec:                        spec_service.active_specialization["name"].downcase,
          spec_id:                     spec_service.active_specialization["id"],
          hero_talent_tree_name:       spec_service.active_hero_tree["name"].downcase,
          hero_talent_tree_id:         spec_service.active_hero_tree["id"],
          raw_specialization:          spec_service.talents
        )
      end

      entry.character.update!(class_slug: spec_service.class_slug) if spec_service.class_slug.present?
    end
  end
end
