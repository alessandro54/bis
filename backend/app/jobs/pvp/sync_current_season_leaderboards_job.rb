module Pvp
  class SyncCurrentSeasonLeaderboardsJob < ApplicationJob
    queue_as :default

    REGIONS = %w[us eu].freeze

    REGION_LOCALES = {
      "us" => "en_US",
      "eu" => "en_GB"
    }.freeze

    # Each region gets its own SolidQueue worker so US and EU API calls never
    # compete for the same worker — and a rate-limit hit on one region doesn't
    # stall the other.
    REGION_QUEUES = {
      "us" => :character_sync_us,
      "eu" => :character_sync_eu
    }.freeze

    # Max simultaneous Blizzard HTTP calls during leaderboard discovery + sync.
    # Raise via PVP_LEADERBOARD_CONCURRENCY env var if rate limits allow.
    MAX_LEADERBOARD_CONCURRENCY = ENV.fetch("PVP_LEADERBOARD_CONCURRENCY", 10).to_i

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def perform(locale: "en_US")
      season = PvpSeason.current
      return unless season

      snapshot_at = Time.current
      sync_cycle = PvpSyncCycle.create!(
        pvp_season:  season,
        regions:     REGIONS,
        snapshot_at: snapshot_at,
        status:      :syncing_leaderboards
      )

      Pvp::SyncLogger.start_cycle(
        cycle_id:    sync_cycle.id,
        season_name: season.display_name,
        regions:     REGIONS
      )

      # Phase 1: Discover brackets for all regions concurrently (parallel HTTP).
      brackets_by_region = discover_all_brackets_concurrently(season, locale)

      # Phase 2: Sync all brackets across all regions concurrently (parallel HTTP).
      # A character that appears in 2v2 AND shuffle is the same record —
      # dedup within the region so it is only fetched from Blizzard once.
      character_ids_by_region = sync_all_leaderboards_concurrently(
        season, brackets_by_region, snapshot_at
      )

      REGIONS.each { |r| character_ids_by_region[r]&.uniq! }

      # Phase 3: Filter recently synced per region, then enqueue each region's
      # batches to its dedicated queue so US and EU process in parallel.
      batch_size       = ENV.fetch("PVP_SYNC_BATCH_SIZE", 50).to_i
      total_batches    = 0
      region_batch_map = {}

      character_ids_by_region.each do |region, char_ids|
        next if char_ids.empty?

        recently_synced = PvpLeaderboardEntry
          .where(character_id: char_ids)
          .where("equipment_processed_at > ?", 1.hour.ago)
          .distinct.pluck(:character_id).to_set

        to_sync = char_ids.reject { |id| recently_synced.include?(id) }

        Rails.logger.info(
          "[SyncCurrentSeasonLeaderboardsJob] #{region}: " \
          "#{char_ids.size} total, #{to_sync.size} need API fetch " \
          "(#{char_ids.size - to_sync.size} recently synced — entries will reuse cache)"
        )
        Pvp::SyncLogger.leaderboards_synced(
          region:  region,
          total:   char_ids.size,
          to_sync: to_sync.size,
          skipped: char_ids.size - to_sync.size
        )

        # Pass ALL character IDs to the batch job — not just `to_sync`.
        # Characters filtered out here still have new entries (created by
        # SyncLeaderboardService) that need equipment/spec data. The batch
        # job handles TTL/cooldown filtering + cached-data propagation.
        region_batch_map[region] = char_ids.each_slice(batch_size).to_a
        total_batches += region_batch_map[region].size
      end

      sync_cycle.update!(
        status:                     :syncing_characters,
        expected_character_batches: total_batches
      )

      if total_batches.zero?
        sync_cycle.update!(status: :completed)
        Pvp::SyncLogger.end_cycle(cycle_id: sync_cycle.id, elapsed_seconds: Time.current - snapshot_at)
        return
      end

      region_batch_map.each do |region, batches|
        queue         = REGION_QUEUES.fetch(region, :character_sync_us)
        region_locale = REGION_LOCALES.fetch(region, locale)

        batches.each do |batch|
          Pvp::SyncCharacterBatchJob
            .set(queue: queue)
            .perform_later(
              character_ids: batch,
              locale:        region_locale,
              sync_cycle_id: sync_cycle.id
            )
        end
      end
    rescue => e
      sync_cycle&.update!(status: :failed) if sync_cycle&.persisted?
      raise
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    private

      # Discover brackets for all regions concurrently via parallel HTTP calls.
      # Uses threads (not Async fibers) because HTTPX runs its own blocking event
      # loop and does not yield to the Async scheduler — threads release the GIL
      # during network I/O so both region requests truly run in parallel.
      def discover_all_brackets_concurrently(season, locale)
        results = run_with_threads(REGIONS, concurrency: REGIONS.size) do |region|
          region_locale = REGION_LOCALES.fetch(region, locale)
          brackets      = discover_brackets(season, region, region_locale)
          { region: region, brackets: brackets, locale: region_locale }
        end

        results.each_with_object({}) { |r, h| h[r[:region]] = r }
      end

      # Sync every bracket across every region concurrently.
      # Returns Hash[region => [character_id, ...]] (not yet deduped).
      # Uses threads for the same reason as discover_all_brackets_concurrently.
      def sync_all_leaderboards_concurrently(season, brackets_by_region, snapshot_at)
        tasks = REGIONS.flat_map do |region|
          info          = brackets_by_region.fetch(region, { brackets: [], locale: REGION_LOCALES[region] })
          region_locale = info[:locale] || REGION_LOCALES[region]
          Array(info[:brackets]).map { |b| { region: region, bracket: b, locale: region_locale } }
        end

        character_ids_by_region = Hash.new { |h, k| h[k] = [] }
        return character_ids_by_region if tasks.empty?

        concurrency = [ tasks.size, MAX_LEADERBOARD_CONCURRENCY ].min

        results = run_with_threads(tasks, concurrency: concurrency) do |task|
          result = Pvp::Leaderboards::SyncLeaderboardService.call(
            season:      season,
            bracket:     task[:bracket],
            region:      task[:region],
            locale:      task[:locale],
            snapshot_at: snapshot_at
          )
          { region: task[:region], ids: result.context[:character_ids] } if result.success?
        rescue => e
          Rails.logger.error(
            "[SyncCurrentSeasonLeaderboardsJob] #{task[:region]}/#{task[:bracket]} failed: #{e.message}"
          )
          nil
        end

        results.each do |r|
          next unless r

          character_ids_by_region[r[:region]].concat(r[:ids] || [])
        end

        character_ids_by_region
      end

      def discover_brackets(season, region, locale)
        response = Blizzard::Api::GameData::PvpSeason::LeaderboardsIndex.fetch(
          pvp_season_id: season.blizzard_id,
          region:        region,
          locale:        locale
        )

        leaderboards  = response.fetch("leaderboards", [])
        bracket_names = leaderboards.map { |lb| lb.dig("name") }.compact

        # Accept 2v2, 3v3, and all shuffle-like brackets; reject RBG/blitz.
        bracket_names.select do |name|
          config = Pvp::BracketConfig.for(name)
          config.present? && config[:job_queue] != :pvp_sync_rbg
        end
      rescue Blizzard::Client::Error => e
        Rails.logger.error(
          "[SyncCurrentSeasonLeaderboardsJob] Failed to discover brackets for #{region}: #{e.message}"
        )
        []
      end
  end
end
