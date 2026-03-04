# frozen_string_literal: true

# Colorized log formatter for development. Adds ANSI colors by severity
# and a compact timestamp. Production uses the default formatter.
class ColorizedLogFormatter < ActiveSupport::Logger::SimpleFormatter
  SEVERITY_BADGES = {
    "DEBUG" => "\e[47;30m",   # white bg, black text
    "INFO"  => "\e[44;37m",   # blue bg, white text
    "WARN"  => "\e[43;30m",   # yellow bg, black text
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
    tag   = severity.center(5)

    "#{DIM}#{ts}#{RESET} #{bg}#{BOLD} #{tag} #{RESET} #{colorize_message(severity, msg)}\n"
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
