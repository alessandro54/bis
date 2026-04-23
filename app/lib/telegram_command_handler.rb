# Handles inbound Telegram bot commands from whitelisted chat IDs.
class TelegramCommandHandler
  COMMANDS = {
    "/help" => :cmd_help,
    "/cycle" => :cmd_cycle,
    "/status" => :cmd_cycle,
    "/errors" => :cmd_errors,
    "/jobs" => :cmd_jobs
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

      /cycle   — current sync cycle status
      /status  — alias for /cycle
      /errors  — job errors in last 24h
      /jobs    — job success rate last 24h
    MSG
    end

    def cmd_cycle
      cycle = PvpSyncCycle.order(created_at: :desc).first
      return TelegramNotifier.reply(@chat_id, "No sync cycles found.") unless cycle

      TelegramNotifier.reply(@chat_id, cycle_message(cycle))
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
        <b>Cycle ##{cycle.id}</b> — #{season&.name || "Season #{season&.id}"}
        Status: <b>#{cycle.status}</b>
        Regions: #{cycle.regions.join(", ")}
        Characters: #{batches}
        Duration: #{elapsed}
        Started: #{cycle.created_at.strftime("%H:%M UTC")}
      MSG
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
end
