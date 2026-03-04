# frozen_string_literal: true

# Colorized Lograge formatter for development.
# Uses background-color badges for HTTP methods, status codes, and log level.
class ColorizedLogrageFormatter
  # Background colors for HTTP methods
  METHOD_BADGES = {
    "GET" => "\e[42;30m", # green bg, black text
    "POST" => "\e[46;30m", # cyan bg, black text
    "PUT" => "\e[43;30m", # yellow bg, black text
    "PATCH" => "\e[43;30m", # yellow bg, black text
    "DELETE" => "\e[41;37m", # red bg, white text
    "HEAD" => "\e[47;30m" # white bg, black text
  }.freeze

  RESET = "\e[0m"
  BOLD  = "\e[1m"
  DIM   = "\e[2m"

  def call(data)
    info     = badge("INFO", "\e[44;37m") # blue bg, white text
    method   = badge(data[:method], METHOD_BADGES.fetch(data[:method].to_s, "\e[47;30m"))
    path     = "#{BOLD}#{data[:path]}#{RESET}"
    status   = status_badge(data[:status])
    duration = colorize_duration(data[:duration])
    db       = data[:db] ? " #{DIM}db=#{data[:db].round(1)}ms#{RESET}" : ""
    view     = data[:view] ? " #{DIM}view=#{data[:view].round(1)}ms#{RESET}" : ""

    extras = data.except(:method, :path, :status, :duration, :db, :view, :format, :controller, :action, :allocations)
    extra_str = extras.any? ? " #{DIM}#{extras.map { |k, v| "#{k}=#{v}" }.join(" ")}#{RESET}" : ""

    "#{info} #{method} #{path} #{status} #{duration}#{db}#{view}#{extra_str}"
  end

  private

    def badge(text, bg_color)
      "#{bg_color}#{BOLD} #{text} #{RESET}"
    end

    def status_badge(status)
      code = status.to_i
      bg = case code
      when 200..299 then "\e[42;30m"   # green bg
      when 300..399 then "\e[46;30m"   # cyan bg
      when 400..499 then "\e[43;30m"   # yellow bg, black text
      when 500..599 then "\e[41;37m"   # red bg, white text
      else "\e[47;30m"
      end
      badge(code, bg)
    end

    def colorize_duration(ms)
      return "" unless ms

      rounded = ms.round(1)
      color = case rounded
      when 0..100   then "\e[32m"   # green — fast
      when 100..500 then "\e[33m"   # yellow — moderate
      else "\e[31m" # red — slow
      end
      "#{color}#{rounded}ms#{RESET}"
    end
end

Rails.application.configure do
  config.lograge.enabled = true

  # Keep original Rails log for ActiveRecord queries in dev
  config.lograge.keep_original_rails_log = Rails.env.development?

  # Production: JSON logs for aggregation (ELK, Datadog, etc.)
  # Development: colorized output
  config.lograge.formatter = if Rails.env.production?
    Lograge::Formatters::Json.new
  else
    ColorizedLogrageFormatter.new
  end

  config.lograge.custom_options = ->(event) do
    extras = {}
    extras[:time] = Time.current.iso8601
    extras[:host] = event.payload[:host]
    extras[:request_id] = event.payload[:request_id]
    extras[:ip] = event.payload[:remote_ip]

    if event.payload[:exception]
      extras[:exception] = event.payload[:exception].first
      extras[:exception_message] = event.payload[:exception].last
    end

    extras.compact
  end

  config.lograge.custom_payload do |controller|
    {
      host:       controller.request.host,
      request_id: controller.request.request_id,
      remote_ip:  controller.request.remote_ip
    }
  end
end
