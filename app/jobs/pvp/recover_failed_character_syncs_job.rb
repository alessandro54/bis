module Pvp
  class RecoverFailedCharacterSyncsJob < ApplicationJob
    queue_as :default

    MAX_RETRIES = 3
    BATCH_SIZE  = 100

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def perform(pvp_sync_cycle_id)
      cycle  = PvpSyncCycle.find(pvp_sync_cycle_id)
      return if cycle.completed? || cycle.failed?

      season  = cycle.pvp_season
      entries = unsynced_entries(season)

      if entries.none?
        Pvp::BuildAggregationsJob.perform_later(pvp_season_id: season.id, sync_cycle_id: cycle.id)
        return
      end

      warn_exhausted(season, entries)

      recoverable = entries.where(sync_retry_count: ...MAX_RETRIES)
      if recoverable.none?
        Pvp::BuildAggregationsJob.perform_later(pvp_season_id: season.id, sync_cycle_id: cycle.id)
        return
      end

      requeue_recoverable(recoverable, cycle)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    private

      def warn_exhausted(season, entries)
        exhausted = entries.where(sync_retry_count: MAX_RETRIES)
        return unless exhausted.any?

        Sentry.capture_message(
          "Characters exhausted sync retries",
          extra: {
            season_id:     season.id,
            count:         exhausted.count,
            character_ids: exhausted.limit(50).pluck(:character_id)
          },
          level: :warning
        )
      end

      def requeue_recoverable(recoverable, cycle)
        batch_count = 0
        recoverable.in_batches(of: BATCH_SIZE) do |batch|
          entry_ids     = batch.pluck(:id)
          character_ids = batch.pluck(:character_id)
          # rubocop:disable Rails/SkipsModelValidations
          PvpLeaderboardEntry.where(id: entry_ids).update_all("sync_retry_count = sync_retry_count + 1")
          # rubocop:enable Rails/SkipsModelValidations
          Pvp::SyncCharacterBatchJob.perform_later(character_ids: character_ids, sync_cycle_id: cycle.id)
          batch_count += 1
        end

        # rubocop:disable Rails/SkipsModelValidations
        cycle.increment!(:expected_character_batches, batch_count)
        # rubocop:enable Rails/SkipsModelValidations
      end

      def unsynced_entries(season)
        PvpLeaderboardEntry
          .joins(:pvp_leaderboard)
          .where(pvp_leaderboards: { pvp_season_id: season.id })
          .where(
            "pvp_leaderboard_entries.equipment_processed_at IS NULL OR " \
            "pvp_leaderboard_entries.specialization_processed_at IS NULL"
          )
      end
  end
end
