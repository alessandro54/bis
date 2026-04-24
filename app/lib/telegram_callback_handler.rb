class TelegramCallbackHandler
  def initialize(chat_id, callback_query_id, data)
    @chat_id           = chat_id.to_s
    @callback_query_id = callback_query_id
    @data              = data.to_s
  end

  def call
    unless TelegramNotifier.allowed?(@chat_id)
      Rails.logger.warn("[TelegramBot] Unauthorized callback chat_id=#{@chat_id}")
      TelegramNotifier.answer_callback_query(@callback_query_id, text: "Unauthorized.")
      return
    end

    action, cycle_id_str = @data.split(":", 2)
    cycle_id = cycle_id_str.to_i

    case action
    when "abort" then handle_abort(cycle_id)
    when "retry" then handle_retry(cycle_id)
    else TelegramNotifier.answer_callback_query(@callback_query_id, text: "Unknown action.")
    end
  end

  private

    def handle_abort(cycle_id)
      cycle = PvpSyncCycle.find_by(id: cycle_id)

      unless cycle
        TelegramNotifier.answer_callback_query(@callback_query_id, text: "Cycle ##{cycle_id} not found.")
        return
      end

      unless cycle.syncing_leaderboards? || cycle.syncing_characters?
        TelegramNotifier.answer_callback_query(@callback_query_id, text: "Cycle ##{cycle_id} is #{cycle.status}.")
        return
      end

      cycle.update!(status: :aborted)
      TelegramNotifier.answer_callback_query(@callback_query_id, text: "Cycle ##{cycle_id} aborted.")
      TelegramNotifier.reply(@chat_id, "🛑 Cycle ##{cycle_id} aborted.")
    end

    def handle_retry(cycle_id)
      cycle = PvpSyncCycle.find_by(id: cycle_id)

      unless cycle
        TelegramNotifier.answer_callback_query(@callback_query_id, text: "Cycle ##{cycle_id} not found.")
        return
      end

      failed_count = PvpLeaderboardEntry
        .joins(:pvp_leaderboard)
        .where(pvp_leaderboards: { pvp_season_id: cycle.pvp_season_id })
        .where("equipment_processed_at IS NULL OR specialization_processed_at IS NULL")
        .count

      if failed_count.zero?
        TelegramNotifier.answer_callback_query(@callback_query_id, text: "No failed characters in Cycle ##{cycle_id}.")
        return
      end

      Pvp::RecoverFailedCharacterSyncsJob.perform_later(cycle_id)
      TelegramNotifier.answer_callback_query(@callback_query_id, text: "Recovery enqueued.")
      TelegramNotifier.reply(@chat_id, "🔄 Recovery enqueued — #{failed_count} characters in Cycle ##{cycle_id}.")
    end
end
