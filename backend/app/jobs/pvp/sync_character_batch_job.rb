module Pvp
  class SyncCharacterBatchJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :character_sync

    def perform(character_ids:, locale: "en_US")
      Array(character_ids).each do |character_id|
        begin
          Pvp::SyncCharacterJob.new.perform(character_id: character_id, locale: locale)
        rescue Blizzard::Client::Error => e
          Rails.logger.warn(
            "[SyncCharacterBatchJob] API error for character #{character_id}, will re-enqueue individual job: #{e.message}"
          )
          Pvp::SyncCharacterJob.perform_later(character_id: character_id, locale: locale)
        rescue StandardError => e
          Rails.logger.error(
            "[SyncCharacterBatchJob] Error for character #{character_id}, will re-enqueue individual job: " \
              "#{e.class}: #{e.message}"
          )
          Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
          Pvp::SyncCharacterJob.perform_later(character_id: character_id, locale: locale)
        end
      end
    end
  end
end
