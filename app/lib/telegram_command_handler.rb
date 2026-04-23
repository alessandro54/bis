# Handles inbound Telegram bot commands from whitelisted chat IDs.
class TelegramCommandHandler
  COMMANDS = {
    "/help" => :cmd_help,
    "/cycle" => :cmd_cycle,
    "/status" => :cmd_cycle,
    "/progress" => :cmd_progress,
    "/history" => :cmd_history,
    "/errors" => :cmd_errors,
    "/jobs" => :cmd_jobs,
    "/syncnow" => :cmd_sync_now,
    "/currentsync" => :cmd_current_sync,
    "/abort" => :cmd_abort
  }.freeze

  def initialize(chat_id, text)
    @chat_id = chat_id.to_s
    @text    = text.to_s.strip
  end

  def call
    unless TelegramNotifier.allowed?(@chat_id)
      Rails.logger.warn("[TelegramBot] Unauthorized chat_id=#{@chat_id}")
      return
    end

    command = @text.split.first&.downcase
    handler = COMMANDS[command]

    if handler
      send(handler)
    else
      TelegramNotifier.reply(@chat_id, "Unknown command. Try /help")
    end
  end

  private

    def cmd_help
      TelegramNotifier.reply(@chat_id, <<~MSG.strip)
      <b>WoW Overseer Bot</b>

      /cycle        — last sync cycle status
      /status       — alias for /cycle
      /progress     — live batch progress + ETA
      /history      — last 5 completed cycles
      /errors       — job errors in last 24h
      /jobs         — job success rate last 24h
      /syncnow      — trigger a sync immediately
      /currentsync  — active cycle details
      /abort &lt;id&gt;  — abort a running cycle
    MSG
    end

    def cmd_cycle
      cycle_id = @text.split[1]&.to_i
      cycle    = if cycle_id&.positive?
        found = PvpSyncCycle.find_by(id: cycle_id)
        return TelegramNotifier.reply(@chat_id, "Cycle ##{cycle_id} not found.") unless found

        found
      else
        PvpSyncCycle.order(created_at: :desc).first
      end

      return TelegramNotifier.reply(@chat_id, "No sync cycles found.") unless cycle

      buttons = cycle_buttons(cycle)
      if buttons.any?
        TelegramNotifier.reply_with_buttons(@chat_id, cycle_message(cycle), buttons)
      else
        TelegramNotifier.reply(@chat_id, cycle_message(cycle))
      end
    end

    def cmd_progress
      cycle = PvpSyncCycle.where(status: :syncing_characters).order(created_at: :desc).first
      cycle ||= PvpSyncCycle.order(created_at: :desc).first
      return TelegramNotifier.reply(@chat_id, "No sync cycles found.") unless cycle

      TelegramNotifier.reply(@chat_id, progress_message(cycle))
    end

    def progress_message(cycle)
      pct     = cycle.progress_pct
      bar     = progress_bar(pct)
      elapsed = format_elapsed(Time.current - cycle.created_at)
      eta_str = cycle.eta_seconds ? " · ETA #{format_elapsed(cycle.eta_seconds)}" : ""
      <<~MSG.strip
        <b>Cycle ##{cycle.id} — #{cycle.status}</b>
        #{bar} #{pct}%
        #{cycle.completed_character_batches}/#{cycle.expected_character_batches} batches · #{elapsed} elapsed#{eta_str}
      MSG
    end

    def cycle_message(cycle)
      season  = cycle.pvp_season
      batches = cycle.expected_character_batches > 0 ?
        "#{cycle.completed_character_batches}/#{cycle.expected_character_batches} batches" :
        "pending"
      elapsed = cycle.completed_at ?
        "#{((cycle.completed_at - cycle.created_at) / 60).round(1)}m" :
        "in progress"

      <<~MSG.strip
        <b>Cycle ##{cycle.id}</b> — Season #{season&.id}
        Status: <b>#{cycle.status}</b>
        Regions: #{cycle.regions.join(", ")}
        Characters: #{batches}
        Duration: #{elapsed}
        Started: #{cycle.created_at.strftime("%H:%M UTC")}
      MSG
    end

    def cmd_history
      cycles = PvpSyncCycle.where(status: :completed)
                           .where.not(completed_at: nil)
                           .order(created_at: :desc)
                           .limit(5)

      if cycles.empty?
        TelegramNotifier.reply(@chat_id, "No completed cycles found.")
        return
      end

      lines = cycles.map do |c|
        duration = "#{((c.completed_at - c.created_at) / 60).round(1)}m"
        "Cycle ##{c.id} · #{duration} · #{c.regions.join('/')}"
      end

      TelegramNotifier.reply(@chat_id, "<b>Last #{cycles.size} completed cycles</b>\n#{lines.join("\n")}")
    end

    def cmd_sync_now
      if (active = PvpSyncCycle.active)
        TelegramNotifier.reply(
          @chat_id,
          "⏭️ Sync already running — Cycle ##{active.id} (#{active.status}, #{active.progress_pct}%)"
        )
        return
      end

      Pvp::SyncCurrentSeasonLeaderboardsJob.perform_later
      TelegramNotifier.reply(@chat_id, "▶️ Sync triggered.")
    end

    def cmd_current_sync
      cycle = PvpSyncCycle.active
      return TelegramNotifier.reply(@chat_id, "No active sync cycle.") unless cycle

      TelegramNotifier.reply(@chat_id, progress_message(cycle))
    end

    def cmd_abort
      cycle_id = @text.split[1]&.to_i
      return TelegramNotifier.reply(@chat_id, "Usage: /abort <cycle_id>") unless cycle_id&.positive?

      cycle = PvpSyncCycle.find_by(id: cycle_id)
      return TelegramNotifier.reply(@chat_id, "Cycle ##{cycle_id} not found.") unless cycle

      unless cycle.syncing_leaderboards? || cycle.syncing_characters?
        return TelegramNotifier.reply(@chat_id, "Cycle ##{cycle_id} is #{cycle.status} — cannot abort.")
      end

      cycle.update!(status: :aborted)
      TelegramNotifier.reply(@chat_id, "🛑 Cycle ##{cycle_id} aborted.")
    end

    def cmd_errors
      dist = JobPerformanceMetric.error_distribution(24.hours)

      if dist.empty?
        TelegramNotifier.reply(@chat_id, "No job errors in the last 24h.")
        return
      end

      lines = dist.sort_by { |_, count| -count }
                  .map { |klass, count| "• #{klass || "unknown"}: #{count}" }
                  .join("\n")

      TelegramNotifier.reply(@chat_id, "<b>Job errors (24h)</b>\n#{lines}")
    end

    def cmd_jobs
      summary = JobPerformanceMetric.performance_summary(time_range: 24.hours)

      TelegramNotifier.reply(@chat_id, <<~MSG.strip)
      <b>Job summary (24h)</b>
      Total: #{summary[:total_jobs]}
      Success: #{summary[:successful_jobs]} (#{summary[:success_rate]}%)
      Failed: #{summary[:failed_jobs]}
      Avg duration: #{summary[:avg_duration]}s
    MSG
    end

    def cycle_buttons(cycle)
      if cycle.syncing_leaderboards? || cycle.syncing_characters?
        [ [ { text: "🛑 Abort", callback_data: "abort:#{cycle.id}" } ] ]
      elsif cycle.failed? || cycle.aborted?
        [ [ { text: "🔄 Retry failed chars", callback_data: "retry:#{cycle.id}" } ] ]
      else
        []
      end
    end

    def progress_bar(pct, width: 10)
      filled = ((pct / 100.0) * width).round
      "█" * filled + "░" * (width - filled)
    end

    def format_elapsed(seconds)
      return "#{seconds.round(0)}s" if seconds < 60

      m = (seconds / 60).floor
      s = (seconds % 60).round
      "#{m}m #{s}s"
    end
end
