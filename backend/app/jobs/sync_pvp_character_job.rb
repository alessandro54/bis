class SyncPvpCharacterJob < ApplicationJob
  self.enqueue_after_transaction_commit = :always
  queue_as :character_sync

  def perform(region:, realm:, name:, entry_id:, locale: "en_US")
    entry = PvpLeaderboardEntry.find_by(id: entry_id)
    return unless entry

    character = entry.character
    return if character.is_private

    snapshot = ::Pvp::Characters::LastEquipmentSnapshotFinderService.call(character_id: character.id)

    if snapshot
      copy_from_snapshot(snapshot, entry)
      return
    end

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

    def copy_from_snapshot(source, target)
      target.update!(
        raw_equipment:               source.raw_equipment,
        raw_specialization:          source.raw_specialization,
        item_level:                  source.item_level,
        tier_set_id:                 source.tier_set_id,
        tier_set_name:               source.tier_set_name,
        tier_set_pieces:             source.tier_set_pieces,
        tier_4p_active:              source.tier_4p_active,
        equipment_processed_at:      source.equipment_processed_at,
        specialization_processed_at: source.specialization_processed_at
      )
    end

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
