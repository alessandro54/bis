module Pvp
  class SyncCharacterBatchJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :character_sync

    def perform(character_ids:, locale: "en_US")
      # Enqueue individual jobs for parallel processing instead of sequential loop
      Array(character_ids).each do |character_id|
        Pvp::SyncCharacterJob.perform_later(character_id: character_id, locale: locale)
      end
    end
  end
end
