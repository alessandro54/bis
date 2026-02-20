module Pvp
  class SyncCharacterBatchJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :character_sync_us  # overridden per-region via .set(queue:) when enqueued

    CONCURRENCY = ENV.fetch("PVP_SYNC_CONCURRENCY", 10).to_i

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

        # Pre-load all latest entries per bracket for every character in one
        # DISTINCT ON query — eliminates N per-character queries in the service.
        entries_by_character_id = batch_load_entries(characters.map(&:id))

        concurrency = safe_concurrency(CONCURRENCY, characters.size)

        run_concurrently(characters, concurrency: concurrency) do |character|
          sync_one(
            character: character,
            locale:    locale,
            outcome:   outcome,
            entries:   entries_by_character_id[character.id] || []
          )
        end
      end

      # Single DISTINCT ON query for all characters; groups results by character_id.
      def batch_load_entries(character_ids)
        PvpLeaderboardEntry
          .joins(:pvp_leaderboard)
          .where(character_id: character_ids)
          .select(
            "DISTINCT ON (pvp_leaderboard_entries.character_id, pvp_leaderboards.bracket) " \
            "pvp_leaderboard_entries.*"
          )
          .order(
            "pvp_leaderboard_entries.character_id, pvp_leaderboards.bracket, " \
            "pvp_leaderboard_entries.snapshot_at DESC, pvp_leaderboard_entries.id DESC"
          )
          .group_by(&:character_id)
      end

      def sync_one(character:, locale:, outcome:, entries: nil)
        return unless character

        ActiveRecord::Base.connection_pool.with_connection do
          result = Pvp::Characters::SyncCharacterService.call(
            character: character,
            locale:    locale,
            entries:   entries
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
        cycle.update!(status: :completed) if cycle.all_character_batches_done?
      rescue => e
        Rails.logger.error(
          "[SyncCharacterBatchJob] Failed to track sync cycle #{@sync_cycle_id}: #{e.message}"
        )
      end
  end
end
