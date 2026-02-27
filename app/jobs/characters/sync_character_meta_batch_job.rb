module Characters
  class SyncCharacterMetaBatchJob < ApplicationJob
    queue_as :character_sync

    def perform(character_ids:)
      characters = Character
        .where(id: character_ids)
        .where(is_private: false)
        .where("meta_synced_at IS NULL OR meta_synced_at < ?", 1.week.ago)

      characters.each do |character|
        Characters::SyncCharacterJob.perform_later(
          region: character.region,
          realm:  character.realm,
          name:   character.name
        )
      end
    end
  end
end
