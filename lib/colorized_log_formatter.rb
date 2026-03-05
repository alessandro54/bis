# frozen_string_literal: true

# Colorized log formatter for development. Adds ANSI background-color badges
# by severity, compact timestamp, and colored messages.
# Production uses the default formatter.
class ColorizedLogFormatter < ActiveSupport::Logger::SimpleFormatter
  SEVERITY_BADGES = {
    "DEBUG" => "\e[47;30m", # white bg, black text
    "INFO" => "\e[44;37m",   # blue bg, white text
    "WARN" => "\e[43;30m",   # yellow bg, black text
    "ERROR" => "\e[41;37m",   # red bg, white text
    "FATAL" => "\e[45;37m"    # magenta bg, white text
  }.freeze

  DIM   = "\e[2m"
  RESET = "\e[0m"
  BOLD  = "\e[1m"

  def call(severity, timestamp, _progname, msg)
    return "" if msg.blank?

    ts    = timestamp.strftime("%H:%M:%S.%L")
    bg    = SEVERITY_BADGES.fetch(severity, "")
    text  = msg.to_s.gsub(/\s*\n\s*/, " ").strip
    pad   = severity.length < 5 ? " " : ""

    "#{DIM}#{ts}#{RESET} #{bg}#{BOLD} #{severity} #{RESET}#{pad} #{colorize_message(severity, text)}\n"
  end

  private

    def colorize_message(severity, msg)
      case severity
      when "DEBUG" then "#{DIM}#{msg}#{RESET}"
      when "ERROR", "FATAL" then "\e[31m#{msg}#{RESET}"
      else msg.to_s
      end
    end
end

# Lograge request formatter for development.
# Uses background-color badges for HTTP methods and status codes.
class ColorizedLogrageFormatter
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

  # rubocop:disable Metrics/AbcSize
  def call(data)
    method   = badge(data[:method], METHOD_BADGES.fetch(data[:method].to_s, "\e[47;30m"))
    path     = "#{BOLD}#{data[:path]}#{RESET}"
    status   = status_badge(data[:status])
    duration = colorize_duration(data[:duration])
    db       = data[:db] ? " #{DIM}db=#{data[:db].round(1)}ms#{RESET}" : ""
    view     = data[:view] ? " #{DIM}view=#{data[:view].round(1)}ms#{RESET}" : ""

    extras = data.except(:method, :path, :status, :duration, :db, :view, :format, :controller, :action, :allocations)
    extra_str = extras.any? ? " #{DIM}#{extras.map { |k, v| "#{k}=#{v}" }.join(" ")}#{RESET}" : ""

    "#{method} #{path} #{status} #{duration}#{db}#{view}#{extra_str}"
  end
  # rubocop:enable Metrics/AbcSize

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
