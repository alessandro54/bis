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

      recover_and_notify(stale)
    end

    private

      def recover_and_notify(cycle)
        elapsed_m = ((Time.current - cycle.created_at) / 60).round(0)

        Pvp::RecoverFailedCharacterSyncsJob.perform_later(cycle.id)

        TelegramNotifier.send(
          "🚨 <b>Stale cycle detected — Cycle ##{cycle.id}</b>\n" \
          "Status: #{cycle.status} · #{elapsed_m}m elapsed · #{cycle.progress_pct}% complete\n" \
          "#{cycle.completed_character_batches}/#{cycle.expected_character_batches} batches\n" \
          "Regions: #{cycle.regions.join(', ')}\n" \
          "⟳ Recovery triggered automatically"
        )
      end
  end
end
