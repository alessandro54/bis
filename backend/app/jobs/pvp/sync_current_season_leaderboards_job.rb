module Pvp
  class SyncCurrentSeasonLeaderboardsJob < ApplicationJob
    queue_as :default

    REGIONS = %w[us eu].freeze

    REGION_LOCALES = {
      "us" => "en_US",
      "eu" => "en_GB"
    }.freeze

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def perform(locale: "en_US")
      season = PvpSeason.current
      return unless season

      snapshot_at = Time.current
      sync_cycle = PvpSyncCycle.create!(
        pvp_season: season,
        regions:    REGIONS,
        snapshot_at: snapshot_at,
        status:     :syncing_leaderboards
      )

      # Phase 1: Sync all regions x all brackets inline, collect character_ids
      all_character_ids = []

      REGIONS.each do |region|
        brackets = discover_brackets(season, region, REGION_LOCALES.fetch(region, locale))

        brackets.each do |bracket|
          result = Pvp::Leaderboards::SyncLeaderboardService.call(
            season:      season,
            bracket:     bracket,
            region:      region,
            locale:      REGION_LOCALES.fetch(region, locale),
            snapshot_at: snapshot_at
          )
          all_character_ids.concat(result.context[:character_ids]) if result.success?
        rescue => e
          Rails.logger.error(
            "[SyncCurrentSeasonLeaderboardsJob] #{region}/#{bracket} failed: #{e.message}"
          )
        end
      end

      # Phase 2: Deduplicate across ALL regions and brackets
      all_character_ids.uniq!

      recently_synced = PvpLeaderboardEntry
        .where(character_id: all_character_ids)
        .where("equipment_processed_at > ?", 1.hour.ago)
        .distinct.pluck(:character_id).to_set

      characters_to_sync = all_character_ids.reject { |id| recently_synced.include?(id) }

      Rails.logger.info(
        "[SyncCurrentSeasonLeaderboardsJob] " \
        "#{all_character_ids.size} total characters, " \
        "#{characters_to_sync.size} to sync (#{all_character_ids.size - characters_to_sync.size} deduped/recently synced)"
      )

      # Enqueue character batches
      batch_size = ENV.fetch("PVP_SYNC_BATCH_SIZE", 50).to_i
      batches = characters_to_sync.each_slice(batch_size).to_a

      sync_cycle.update!(
        status: :syncing_characters,
        expected_character_batches: batches.size
      )

      if batches.empty?
        Pvp::BuildAggregationsJob.perform_later(sync_cycle_id: sync_cycle.id)
        return
      end

      batches.each do |batch|
        Pvp::SyncCharacterBatchJob.perform_later(
          character_ids:  batch,
          locale:         locale,
          sync_cycle_id:  sync_cycle.id
        )
      end
    rescue => e
      sync_cycle&.update(status: :failed) if sync_cycle&.persisted?
      raise
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    private

      def discover_brackets(season, region, locale)
        response = Blizzard::Api::GameData::PvpSeason::LeaderboardsIndex.fetch(
          pvp_season_id: season.blizzard_id,
          region:        region,
          locale:        locale
        )

        leaderboards = response.fetch("leaderboards", [])
        bracket_names = leaderboards.map { |lb| lb.dig("name") }.compact

        # Only keep brackets that have a known config
        bracket_names.select { |name| Pvp::BracketConfig.for(name) }
      rescue Blizzard::Client::Error => e
        Rails.logger.error(
          "[SyncCurrentSeasonLeaderboardsJob] Failed to discover brackets for #{region}: #{e.message}"
        )
        []
      end
  end
end
