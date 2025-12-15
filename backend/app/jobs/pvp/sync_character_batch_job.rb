module Pvp
  class SyncCharacterBatchJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :character_sync

    def perform(character_ids:, locale: "en_US")
      Array(character_ids).each do |character_id|
        result = Pvp::Characters::SyncCharacterService.call(
          character: Character.find_by(id: character_id),
          locale:    locale
        )

        next if result.success?

        log_batch_error(character_id, result.error)
        Pvp::SyncCharacterJob.perform_later(character_id: character_id, locale: locale)
      rescue StandardError => e
        log_batch_error(character_id, e)
        Pvp::SyncCharacterJob.perform_later(character_id: character_id, locale: locale)
      end
    end

    private

      def log_batch_error(character_id, error)
        Rails.logger.error(
          "[SyncCharacterBatchJob] Error for character #{character_id}, will re-enqueue individual job: " \
            "#{error.class}: #{error.message}"
        )
        Rails.logger.error(error.backtrace&.first(10)&.join("\n")) if error.respond_to?(:backtrace)
      end
  end
end
