# frozen_string_literal: true

# Colorized log formatter for development. Adds ANSI colors by severity
# and a compact timestamp. Production uses the default formatter.
class ColorizedLogFormatter < ActiveSupport::Logger::SimpleFormatter
  SEVERITY_COLORS = {
    "DEBUG" => "\e[36m",  # cyan
    "INFO"  => "\e[32m",  # green
    "WARN"  => "\e[33m",  # yellow
    "ERROR" => "\e[31m",  # red
    "FATAL" => "\e[35;1m" # bold magenta
  }.freeze

  DIM   = "\e[2m"
  RESET = "\e[0m"
  BOLD  = "\e[1m"

  def call(severity, timestamp, _progname, msg)
    return "" if msg.blank?

    color = SEVERITY_COLORS.fetch(severity, "")
    ts    = timestamp.strftime("%H:%M:%S.%L")
    tag   = severity[0] # D, I, W, E, F

    "#{DIM}#{ts}#{RESET} #{color}#{BOLD}#{tag}#{RESET} #{colorize_message(severity, msg)}\n"
  end

  private

    def colorize_message(severity, msg)
      case severity
      when "DEBUG" then "#{DIM}#{msg}#{RESET}"
      when "ERROR", "FATAL" then "#{SEVERITY_COLORS[severity]}#{msg}#{RESET}"
      else msg.to_s
      end
    end
end
