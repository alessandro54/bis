module Pvp
  # Dedicated logger for the PvP sync pipeline.
  #
  # Writes structured, human-readable sync events to log/pvp_sync.log,
  # separate from the main Rails log (which is noisy with SQL queries).
  #
  # Usage pattern per sync run:
  #
  #   SyncLogger.start_cycle(...)           # SyncCurrentSeasonLeaderboardsJob
  #   SyncLogger.leaderboards_synced(...)   # per region, same job
  #   SyncLogger.batch_complete(...)        # SyncCharacterBatchJob, once per batch
  #   SyncLogger.aggregations_complete(...) # BuildAggregationsJob
  #   SyncLogger.end_cycle(...)             # BuildAggregationsJob, prints closing separator
  #
  module SyncLogger
    LOG_PATH  = Rails.root.join("log", "pvp_sync.log")
    SEPARATOR = ("═" * 80).freeze

    def self.logger
      @logger ||= begin
        logger = Logger.new(LOG_PATH, "daily", progname: "pvp_sync")
        logger.formatter = proc do |_severity, datetime, _progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{msg}\n"
        end
        logger
      end
    end

    # ── Cycle start ──────────────────────────────────────────────────────────

    def self.start_cycle(cycle_id:, season_name:, regions:)
      logger.info(SEPARATOR)
      logger.info(
        "SYNC CYCLE ##{cycle_id} STARTED  |  Season: #{season_name}  |  Regions: #{regions.join(', ')}"
      )
      logger.info(SEPARATOR)
    end

    # ── Phase 1 — Leaderboard discovery ─────────────────────────────────────

    def self.leaderboards_synced(region:, total:, to_sync:, skipped:)
      logger.info(
        "  [leaderboards] #{region.upcase.ljust(3)}  " \
        "#{total} chars → #{to_sync} to sync  (#{skipped} recently synced)"
      )
    end

    # ── Phase 2 — Character batch sync ───────────────────────────────────────

    def self.batch_complete(outcome:)
      succeeded = outcome.successes.size
      failed    = outcome.failures.size
      total     = outcome.total

      counts = outcome.counts_by_status
                      .map { |status, count| "#{status}: #{count}" }
                      .join(", ")

      line = "  [batch]  #{succeeded}/#{total} ok"
      line += ", #{failed} failed" if failed > 0
      line += "  { #{counts} }"

      if outcome.failures.any?
        samples = outcome.failures.first(3).map { |f| "char #{f[:id]}: #{f[:error]}" }.join(" | ")
        line += "  ⚠ #{samples}"
        line += " (+#{failed - 3} more)" if failed > 3
      end

      logger.info(line)
    end

    # ── Phase 3 — Aggregations ───────────────────────────────────────────────

    def self.aggregations_complete(items:, enchants:, gems:)
      logger.info(
        "  [aggregations]  items=#{items}  enchants=#{enchants}  gems=#{gems}"
      )
    end

    # ── Cycle end ─────────────────────────────────────────────────────────────

    def self.end_cycle(cycle_id:, elapsed_seconds: nil)
      elapsed = elapsed_seconds ? "  (#{format_elapsed(elapsed_seconds)})" : ""
      logger.info("SYNC CYCLE ##{cycle_id} COMPLETE#{elapsed}")
      logger.info(SEPARATOR)
      logger.info("")
    end

    # ── Errors ────────────────────────────────────────────────────────────────

    def self.error(message)
      logger.error("  [error]  #{message}")
    end

    private_class_method def self.format_elapsed(seconds)
      return "#{seconds.round(1)}s" if seconds < 60

      m = (seconds / 60).floor
      s = (seconds % 60).round
      "#{m}m #{s}s"
    end
  end
end
