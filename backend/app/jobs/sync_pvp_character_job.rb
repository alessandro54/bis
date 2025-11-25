class SyncPvpCharacterJob < ApplicationJob
  queue_as :default

  EXCLUDED_SLOTS = %w[TABARD SHIRT].freeze

  def perform(region:, realm:, name:, entry_id:, locale: "en_US")
    entry = PvpLeaderboardEntry.find(entry_id)
    character = entry.character

    equipment_json = safe_fetch do
      Blizzard::Api::Profile::CharacterEquipmentSummary.fetch(
        region:, realm:, name:, locale:
      )
    end
    return unless equipment_json

    talents_json = safe_fetch do
      Blizzard::Api::Profile::CharacterSpecializationSummary.fetch(
        region:, realm:, name:, locale:
      )
    end
    return unless talents_json

    enrich_entry_from_api(entry, character, equipment_json, talents_json, locale:)
  end

  private

    def safe_fetch
      yield
    rescue Blizzard::Client::Error => e
      handle_blizzard_error(e)
      nil
    end

    def enrich_entry_from_api(entry, character, equipment_json, talents_json, locale:)
      update_data = {}

      entry.update!(
        raw_equipment:      equipment_json,
        raw_specialization: talents_json,
      )

      Pvp::LeaderboardEntryProcessEquipmentJob.perform_later(
        entry_id: entry.id,
        locale:   locale
      )

      apply_talents(update_data, character, talents_json)

      return if update_data.empty?

      Rails.logger.silence { entry.update!(update_data) }
    end

    def apply_talents(update_data, character, talents)
      spec_service = Blizzard::Data::CharacterEquipmentSpecializationsService.new(talents)
      return unless spec_service.has_data?

      update_data[:spec] = spec_service.active_specialization["name"].downcase
      update_data[:spec_id] = spec_service.active_specialization["id"]

      update_data[:hero_talent_tree_name] = spec_service.active_hero_tree["name"].downcase
      update_data[:hero_talent_tree_id] = spec_service.active_hero_tree["id"]

      character.update!(class_slug: spec_service.class_slug) if spec_service.class_slug.present?

      update_data[:raw_specialization] = spec_service.talents
    end

    def handle_blizzard_error(e)
      if e.message.include?("404")
        Rails.logger.warn("[SyncPvpCharacterJob] 404 → profile private or deleted")
      else
        Rails.logger.error("[SyncPvpCharacterJob] Error: #{e.message}")
      end
    end
end
