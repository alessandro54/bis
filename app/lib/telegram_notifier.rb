require "net/http"
require "uri"

# Sends fire-and-forget Telegram messages via Bot API.
# No-ops silently when TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID are unset.
module TelegramNotifier
  API_URL = "https://api.telegram.org"

  # rubocop:disable Metrics/AbcSize
  def self.send(text)
    token = ENV["TELEGRAM_BOT_TOKEN"]
    chat  = ENV["TELEGRAM_CHAT_ID"]
    return unless token.present? && chat.present?

    uri  = URI("#{API_URL}/bot#{token}/sendMessage")
    body = URI.encode_www_form(chat_id: chat, text: text, parse_mode: "HTML")

    http           = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl   = true
    http.open_timeout = 3
    http.read_timeout = 5

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/x-www-form-urlencoded"
    request.body = body

    http.request(request)
  rescue StandardError => e
    Rails.logger.error("[TelegramNotifier] #{e.message}")
  end
  # rubocop:enable Metrics/AbcSize
end
