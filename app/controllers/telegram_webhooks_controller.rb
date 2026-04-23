class TelegramWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  WEBHOOK_SECRET = ENV["TELEGRAM_WEBHOOK_SECRET"]

  def create
    if WEBHOOK_SECRET.present? && request.headers["X-Telegram-Bot-Api-Secret-Token"] != WEBHOOK_SECRET
      head :unauthorized
      return
    end

    update  = params.permit!.to_h
    message = update.dig("message") || update.dig("edited_message")

    if message
      chat_id = message.dig("chat", "id")
      text    = message["text"].to_s

      TelegramCommandHandler.new(chat_id, text).call if text.start_with?("/")
    end

    head :ok
  end
end
