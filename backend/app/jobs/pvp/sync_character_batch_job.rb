module Pvp
  class SyncCharacterBatchJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :character_sync

    CONCURRENCY = ENV.fetch("PVP_SYNC_CONCURRENCY", 5).to_i

    retry_on Blizzard::Client::Error, wait: :polynomially_longer, attempts: 3 do |_job, error|
      Rails.logger.warn("[SyncCharacterBatchJob] API error, will retry: #{error.message}")
    end

    def perform(character_ids:, locale: "en_US", sync_cycle_id: nil)
      @sync_cycle_id = sync_cycle_id

      ids = Array(character_ids).compact
      return if ids.empty?

      characters_by_id = Character
        .where(id: ids)
        .where(is_private: false)
        .index_by(&:id)

      return if characters_by_id.empty?

      outcome = BatchOutcome.new

      # Characters are fetched from the Blizzard API and processed inline —
      # equipment and talents are written directly to character_items /
      # character_talents without an intermediate blob storage step.
      process_characters_concurrently(characters_by_id.values, locale, outcome)

      Rails.logger.info(outcome.summary_message(job_label: "SyncCharacterBatchJob"))
      outcome.raise_if_total_failure!(job_label: "SyncCharacterBatchJob")
    ensure
      track_sync_cycle_completion
    end

    private

      def process_characters_concurrently(characters, locale, outcome)
        return if characters.empty?

        concurrency = safe_concurrency(CONCURRENCY, characters.size)

        run_concurrently(characters, concurrency: concurrency) do |character|
          sync_one(character: character, locale: locale, outcome: outcome)
        end
      end

      def sync_one(character:, locale:, outcome:)
        return unless character

        ActiveRecord::Base.connection_pool.with_connection do
          result = Pvp::Characters::SyncCharacterService.call(
            character: character,
            locale:    locale
          )

          if result.success?
            outcome.record_success(id: character.id, status: result.context[:status])
          else
            outcome.record_failure(id: character.id, status: :failed, error: result.error.to_s)
          end
        end
      rescue Blizzard::Client::RateLimitedError => e
        Rails.logger.warn(
          "[SyncCharacterBatchJob] Rate limited for character #{character&.id}: #{e.message}"
        )
        outcome.record_failure(id: character&.id, status: :rate_limited, error: e.message)
      rescue Blizzard::Client::Error => e
        Rails.logger.warn(
          "[SyncCharacterBatchJob] API error for character #{character&.id}: #{e.message}"
        )
        outcome.record_failure(id: character&.id, status: :api_error, error: e.message)
      rescue => e
        Rails.logger.error(
          "[SyncCharacterBatchJob] Unexpected error for character #{character&.id}: #{e.class}: #{e.message}"
        )
        outcome.record_failure(id: character&.id, status: :unexpected_error, error: "#{e.class}: #{e.message}")
      end

      def track_sync_cycle_completion
        return unless @sync_cycle_id

        cycle = PvpSyncCycle.find_by(id: @sync_cycle_id)
        return unless cycle

        cycle.increment_completed_character_batches!

        if cycle.all_character_batches_done?
          Pvp::BuildAggregationsJob.perform_later(sync_cycle_id: @sync_cycle_id)
        end
      rescue => e
        Rails.logger.error(
          "[SyncCharacterBatchJob] Failed to track sync cycle #{@sync_cycle_id}: #{e.message}"
        )
      end
  end
end
