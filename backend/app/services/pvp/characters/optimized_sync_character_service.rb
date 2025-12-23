# Optimized character sync service with bulk operations and intelligent caching
module Pvp
  module Characters
    class OptimizedSyncCharacterService < ApplicationService
      def initialize(character:, locale: "en_US", ttl_hours: DEFAULT_TTL_HOURS)
        @character = character
        @locale = locale
        @ttl_hours = ttl_hours
      end

      def call
        return failure("Character not found") unless character
        return success(character) unless needs_sync?

        # Use bulk API calls when possible
        sync_result = perform_bulk_sync
        return sync_result if sync_result.failure?

        # Queue processing jobs in bulk if needed
        queue_processing_jobs

        success(character)
      rescue => e
        failure(e)
      end

      private

        attr_reader :character, :locale, :ttl_hours

        def needs_sync?
          character.meta_synced_at.nil? ||
          character.meta_synced_at < 1.hour.ago ||
          character.pvp_leaderboard_entries.where(
            "equipment_processed_at IS NULL OR specialization_processed_at IS NULL"
          ).exists?
        end

        def perform_bulk_sync
          # Use cached Blizzard client for better performance
          client = Blizzard::Client.new(locale: locale, use_cache: true)

          # Fetch character data with optimized API calls
          character_data = fetch_character_data(client)
          return failure("Failed to fetch character data") unless character_data

          # Update character in bulk
          update_character_bulk(character_data)

          # Update associated records in bulk
          update_leaderboard_entries_bulk(character_data)

          success(character)
        end

        def fetch_character_data(client)
          # Parallel API calls for better performance
          require "concurrent-ruby"

          pool = Concurrent::ThreadPoolExecutor.new(max_threads: 3)

          futures = [
            Concurrent::Future.execute(executor: pool) { client.character_profile(character) },
            Concurrent::Future.execute(executor: pool) { client.character_pvp_stats(character) },
            Concurrent::Future.execute(executor: pool) { client.character_equipment_summary(character) }
          ]

          results = futures.map(&:value!)
          pool.shutdown

          return nil if results.any?(&:nil?)

          {
            profile:           results[0],
            pvp_stats:         results[1],
            equipment_summary: results[2]
          }
        end

        def update_character_bulk(data)
          character.update!(
            meta_synced_at: Time.current,
            # Add other character fields as needed
            updated_at:     Time.current
          )
        end

        def update_leaderboard_entries_bulk(data)
          # Find all entries that need updating
          entries_to_update = character.pvp_leaderboard_entries.where(
            "equipment_processed_at IS NULL OR specialization_processed_at IS NULL"
          )

          return if entries_to_update.empty?

          # Update in bulk to reduce database load
          # rubocop:disable Rails/SkipsModelValidations - Bulk operation for performance
          entries_to_update.update_all(
            raw_specialization: data[:pvp_stats]&.to_json,
            raw_equipment:      data[:equipment_summary]&.to_json,
            updated_at:         Time.current
          )
          # rubocop:enable Rails/SkipsModelValidations

          # Queue processing jobs in bulk
          Pvp::OptimizedProcessLeaderboardEntryBatchJob.perform_later(
            entry_ids: entries_to_update.pluck(:id),
            locale:    locale
          )
        end

        def queue_processing_jobs
          # Only queue if we have entries that need processing
          entries_needing_processing = character.pvp_leaderboard_entries.where(
            "equipment_processed_at IS NULL OR specialization_processed_at IS NULL"
          )

          return if entries_needing_processing.empty?

          # Process in optimized batches
          Pvp::OptimizedProcessLeaderboardEntryBatchJob.perform_later(
            entry_ids: entries_needing_processing.pluck(:id),
            locale:    locale
          )
        end
    end
  end
end
