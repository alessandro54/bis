module Pvp
  class NotifyCycleProgressJob < ApplicationJob
    queue_as :default

    def perform(cycle_id, milestone)
      cycle = PvpSyncCycle.find_by(id: cycle_id)
      return unless cycle

      elapsed = format_elapsed(Time.current - cycle.created_at)
      eta_str = cycle.eta_seconds ? " · ETA #{format_elapsed(cycle.eta_seconds)}" : ""

      TelegramNotifier.send(
        "⏳ <b>Cycle ##{cycle.id} — #{milestone}% complete</b>\n" \
        "Season #{cycle.pvp_season_id} · Regions: #{cycle.regions.join(', ')}\n" \
        "#{cycle.completed_character_batches}/#{cycle.expected_character_batches} batches" \
        " · #{elapsed} elapsed#{eta_str}"
      )
    end

    private

      def format_elapsed(seconds)
        return "#{seconds.round(0)}s" if seconds < 60

        m = (seconds / 60).floor
        s = (seconds % 60).round
        "#{m}m #{s}s"
      end
  end
end
