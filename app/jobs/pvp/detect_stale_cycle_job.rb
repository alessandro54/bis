module Pvp
  class DetectStaleCycleJob < ApplicationJob
    queue_as :default

    STALE_THRESHOLD_MINUTES = 120
    AUTO_ABORT_THRESHOLD_HOURS = 24

    def perform
      stale_cycles = PvpSyncCycle
        .where(status: %i[syncing_leaderboards syncing_characters])
        .where("updated_at < ?", STALE_THRESHOLD_MINUTES.minutes.ago)
        .order(created_at: :asc)

      stale_cycles.each do |cycle|
        if (Time.current - cycle.created_at) >= AUTO_ABORT_THRESHOLD_HOURS.hours
          auto_abort(cycle)
        else
          recover_and_notify(cycle)
        end
      end
    end

    private

      def auto_abort(cycle)
        cycle.update!(status: :aborted)

        TelegramNotifier.send(
          "🛑 <b>Cycle ##{cycle.id} auto-aborted</b> — stuck &gt;#{AUTO_ABORT_THRESHOLD_HOURS}h\n" \
          "#{cycle.completed_character_batches}/#{cycle.expected_character_batches} batches " \
          "(#{cycle.progress_pct}%)\nRegions: #{cycle.regions.join(', ')}"
        )
      end

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
