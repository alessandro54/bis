module Pvp
  class DetectStaleCycleJob < ApplicationJob
    queue_as :default

    STALE_THRESHOLD_MINUTES = 120

    def perform
      stale = PvpSyncCycle
        .where(status: :syncing_characters)
        .where("updated_at < ?", STALE_THRESHOLD_MINUTES.minutes.ago)
        .order(created_at: :desc)
        .first

      return unless stale

      elapsed_m = ((Time.current - stale.created_at) / 60).round(0)
      pct = stale.progress_pct

      TelegramNotifier.send(
        "🚨 <b>Stale cycle detected — Cycle ##{stale.id}</b>\n" \
        "Status: #{stale.status} · #{elapsed_m}m elapsed · #{pct}% complete\n" \
        "#{stale.completed_character_batches}/#{stale.expected_character_batches} batches\n" \
        "Regions: #{stale.regions.join(', ')}"
      )
    end
  end
end
