module Pvp
  class SyncCharacterJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :character_sync

    # Retry on API errors with exponential backoff (network issues, rate limits, etc.)
    retry_on Blizzard::Client::Error, wait: :exponentially_longer, attempts: 3 do |job, error|
      Rails.logger.warn("[SyncCharacterJob] API error, will retry: #{error.message}")
    end

    def perform(character_id:, locale: "en_US")
      result = Pvp::Characters::SyncCharacterService.call(
        character: Character.find_by(id: character_id),
        locale:    locale
      )

      return if result.success?

      error_message = "[SyncCharacterJob] Failed for character #{character_id}: #{result.error}"
      Rails.logger.error(error_message)

      raise(result.error) if result.error.is_a?(Exception)
      raise(StandardError, error_message)
    end
  end
end
