require "net/http"
require "uri"

# Sends fire-and-forget Telegram messages via Bot API.
# No-ops silently when TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID are unset.
module TelegramNotifier
  API_URL = "https://api.telegram.org"

  def self.allowed_chat_ids
    raw = ENV["TELEGRAM_ALLOWED_CHAT_IDS"].to_s
    raw.split(",").map(&:strip).reject(&:empty?)
  end

  def self.allowed?(chat_id)
    allowed_chat_ids.include?(chat_id.to_s)
  end

  # Broadcast to the default TELEGRAM_CHAT_ID (job notifications).
  # rubocop:disable Metrics/AbcSize
  def self.send(text)
    token = ENV["TELEGRAM_BOT_TOKEN"]
    chat  = ENV["TELEGRAM_CHAT_ID"]
    return unless token.present? && chat.present?

    post_message(token, chat, text)
  end

  # Reply to a specific chat_id (bot commands).
  def self.reply(chat_id, text)
    token = ENV["TELEGRAM_BOT_TOKEN"]
    return unless token.present?

    post_message(token, chat_id, text)
  end
  # rubocop:enable Metrics/AbcSize

  def self.post_message(token, chat_id, text)
    uri  = URI("#{API_URL}/bot#{token}/sendMessage")
    body = URI.encode_www_form(chat_id: chat_id, text: text, parse_mode: "HTML")

    http              = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl      = true
    http.open_timeout = 3
    http.read_timeout = 5

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/x-www-form-urlencoded"
    request.body = body

    http.request(request)
  rescue StandardError => e
    Rails.logger.error("[TelegramNotifier] #{e.message}")
  end
  private_class_method :post_message
end
