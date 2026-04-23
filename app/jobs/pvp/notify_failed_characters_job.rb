module Pvp
  class NotifyFailedCharactersJob < ApplicationJob
    queue_as :default

    FAILURE_THRESHOLD_PCT = 5.0

    def perform(cycle_id, total:, failed:)
      return if failed.zero?
      return if (failed.to_f / total * 100) < FAILURE_THRESHOLD_PCT

      characters = failed_characters(cycle_id)
      return if characters.empty?

      content  = build_report(characters, failed, total)
      filename = "failed_characters_cycle_#{cycle_id}.txt"
      pct     = (failed.to_f / total * 100).round(1)
      caption = "⚠️ Cycle ##{cycle_id} — #{failed}/#{total} characters failed (#{pct}%)"

      TelegramNotifier.send_document(filename: filename, content: content, caption: caption)
    end

    private

      def failed_characters(cycle_id)
        cycle = PvpSyncCycle.find_by(id: cycle_id)
        return [] unless cycle

        PvpLeaderboardEntry
          .joins(:pvp_leaderboard, :character)
          .where(pvp_leaderboards: { pvp_season_id: cycle.pvp_season_id })
          .where("pvp_leaderboard_entries.equipment_processed_at IS NULL OR " \
                 "pvp_leaderboard_entries.specialization_processed_at IS NULL")
          .pluck("characters.name", "characters.realm", "characters.region")
      end

      def build_report(characters, failed, total)
        lines = [ "Failed Characters Report", "Total: #{failed}/#{total}", "=" * 40, "" ]
        lines += characters.map { |name, realm, region| "#{region.upcase}/#{realm}/#{name}" }
        lines.join("\n")
      end
  end
end
