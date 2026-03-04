# frozen_string_literal: true

# Colorized Lograge formatter for development.
# Paints HTTP methods, status codes, and durations with ANSI colors.
class ColorizedLogrageFormatter
  METHOD_COLORS = {
    "GET"    => "\e[32m",    # green
    "POST"   => "\e[36m",    # cyan
    "PUT"    => "\e[33m",    # yellow
    "PATCH"  => "\e[33m",    # yellow
    "DELETE" => "\e[31m",    # red
    "HEAD"   => "\e[2m"      # dim
  }.freeze

  RESET = "\e[0m"
  BOLD  = "\e[1m"
  DIM   = "\e[2m"

  def call(data)
    method   = colorize_method(data[:method])
    path     = "#{BOLD}#{data[:path]}#{RESET}"
    status   = colorize_status(data[:status])
    duration = colorize_duration(data[:duration])
    db       = data[:db] ? " #{DIM}db=#{data[:db].round(1)}ms#{RESET}" : ""
    view     = data[:view] ? " #{DIM}view=#{data[:view].round(1)}ms#{RESET}" : ""

    extras = data.except(:method, :path, :status, :duration, :db, :view, :format, :controller, :action, :allocations)
    extra_str = extras.any? ? " #{DIM}#{extras.map { |k, v| "#{k}=#{v}" }.join(" ")}#{RESET}" : ""

    "#{method} #{path} #{status} #{duration}#{db}#{view}#{extra_str}"
  end

  private

    def colorize_method(method)
      color = METHOD_COLORS.fetch(method.to_s, "")
      "#{color}#{BOLD}#{method}#{RESET}"
    end

    def colorize_status(status)
      code = status.to_i
      color = case code
              when 200..299 then "\e[32m"   # green
              when 300..399 then "\e[36m"   # cyan
              when 400..499 then "\e[33m"   # yellow
              when 500..599 then "\e[31;1m" # bold red
              else ""
              end
      "#{color}#{code}#{RESET}"
    end

    def colorize_duration(ms)
      return "" unless ms

      rounded = ms.round(1)
      color = case rounded
              when 0..100   then "\e[32m"   # green — fast
              when 100..500 then "\e[33m"   # yellow — moderate
              else               "\e[31m"   # red — slow
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
