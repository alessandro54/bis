class TelegramWebhooksController < ApplicationController
  WEBHOOK_SECRET = ENV["TELEGRAM_WEBHOOK_SECRET"]

  def create
    if WEBHOOK_SECRET.present? && request.headers["X-Telegram-Bot-Api-Secret-Token"] != WEBHOOK_SECRET
      head :unauthorized
      return
    end

    update = params.permit!.to_h
    dispatch_message(update.dig("message") || update.dig("edited_message")) ||
      dispatch_callback(update.dig("callback_query"))

    head :ok
  end

  private

    def dispatch_message(message)
      return false unless message

      chat_id = message.dig("chat", "id")
      text    = message["text"].to_s
      TelegramCommandHandler.new(chat_id, text).call if text.start_with?("/")
      true
    end

    def dispatch_callback(cq)
      return false unless cq

      TelegramCallbackHandler.new(
        cq.dig("message", "chat", "id"),
        cq["id"],
        cq["data"].to_s
      ).call
      true
    end
end
