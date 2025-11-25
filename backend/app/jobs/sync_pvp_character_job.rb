class SyncPvpCharacterJob < ApplicationJob
  queue_as :default

  def perform(region:, realm:, name:, entry_id:, locale: "en_US")
    entry = PvpLeaderboardEntry.find(entry_id)

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

    Rails.logger.silence do
      entry.update!(
        raw_equipment:      equipment_json,
        raw_specialization: talents_json
      )
    end

    Pvp::ProcessLeaderboardEntryEquipmentJob.perform_later(entry_id: entry.id, locale:)
    Pvp::ProcessLeaderboardEntrySpecializationJob.perform_later(entry_id: entry.id, locale:)
  end

  private

    def safe_fetch
      yield
    rescue Blizzard::Client::Error => e
      handle_blizzard_error(e)
      nil
    end

    def handle_blizzard_error(e)
      if e.message.include?("404")
        Rails.logger.warn("[SyncPvpCharacterJob] 404 → profile private or deleted")
      else
        Rails.logger.error("[SyncPvpCharacterJob] Error: #{e.message}")
      end
    end
end
