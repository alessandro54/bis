module Pvp
  class BuildAggregationsJob < ApplicationJob
    queue_as :default

    AGGREGATIONS = [
      [ :items,    Pvp::Meta::ItemAggregationService,    PvpMetaItemPopularity    ],
      [ :enchants, Pvp::Meta::EnchantAggregationService, PvpMetaEnchantPopularity ],
      [ :gems,     Pvp::Meta::GemAggregationService,     PvpMetaGemPopularity     ],
      [ :talents,  Pvp::Meta::TalentAggregationService,  PvpMetaTalentPopularity  ]
    ].freeze

    def perform(pvp_season_id:, sync_cycle_id: nil, cycle_started_at: nil)
      season = find_season!(pvp_season_id)
      return unless season

      cycle   = sync_cycle_id ? PvpSyncCycle.find_by(id: sync_cycle_id) : nil
      results = run_aggregations(season, cycle)

      log_completion(pvp_season_id, results)
      if cycle
        handle_cycle_results(season, cycle, results, cycle_started_at)
      else
        sync_log_completion(results)
        end_cycle_if_needed(sync_cycle_id, cycle_started_at)
      end
    end

    private

      def find_season!(pvp_season_id)
        season = PvpSeason.find_by(id: pvp_season_id)
        return season if season

        Rails.logger.warn("[BuildAggregationsJob] Season #{pvp_season_id} not found, skipping")
        nil
      end

      def handle_cycle_results(season, cycle, results, cycle_started_at)
        if results.values.all? { |v| v != :failed }
          promote_cycle(season, cycle, results, cycle_started_at)
        else
          rollback_draft(cycle)
          Sentry.capture_message(
            "Aggregation cycle failed — live data preserved",
            extra: {
              cycle_id: cycle.id,
              failures: results.select { |_, v| v == :failed }.keys
            }
          )
        end
      end

      def run_aggregations(season, cycle)
        results = run_with_threads(AGGREGATIONS, concurrency: AGGREGATIONS.size) do |tuple|
          key, service_class, _model_class = tuple
          run_single_aggregation(key, service_class, season, cycle)
        end
        results.to_h
      end

      def run_single_aggregation(key, service_class, season, cycle)
        result = service_class.call(season: season, cycle: cycle)
        if result.success?
          [ key, result.context[:count] ]
        else
          log_aggregation_failure(service_class, season.id, result.error)
          [ key, :failed ]
        end
      end

      def promote_cycle(season, cycle, results, cycle_started_at)
        ApplicationRecord.transaction do
          old_cycle_id = season.live_pvp_sync_cycle_id
          season.update!(live_pvp_sync_cycle_id: cycle.id)
          cycle.update!(status: :completed)
          purge_old_cycle_data(old_cycle_id) if old_cycle_id
        end
        clear_meta_cache
        log_sync_report(season, cycle, results, cycle_started_at)
      end

      def rollback_draft(cycle)
        ApplicationRecord.transaction do
          popularity_models.each { |m| m.where(pvp_sync_cycle_id: cycle.id).delete_all }
          cycle.update!(status: :failed)
        end
      end

      def purge_old_cycle_data(old_cycle_id)
        popularity_models.each do |model|
          model.where(pvp_sync_cycle_id: old_cycle_id).delete_all
        end
      end

      def popularity_models
        [ PvpMetaItemPopularity, PvpMetaEnchantPopularity,
          PvpMetaGemPopularity,  PvpMetaTalentPopularity ]
      end

      def log_sync_report(season, cycle, results, cycle_started_at)
        total  = PvpLeaderboardEntry
                   .joins(:pvp_leaderboard)
                   .where(pvp_leaderboards: { pvp_season_id: season.id })
                   .count
        failed = PvpLeaderboardEntry
                   .joins(:pvp_leaderboard)
                   .where(pvp_leaderboards: { pvp_season_id: season.id })
                   .where("equipment_processed_at IS NULL OR specialization_processed_at IS NULL")
                   .count
        Pvp::SyncLogger.cycle_complete(
          cycle:              cycle,
          season_name:        season.display_name,
          synced:             total - failed,
          total:              total,
          failed:             failed,
          aggregation_counts: results,
          elapsed_seconds:    compute_elapsed_seconds(cycle_started_at)
        )
      end

      def log_aggregation_failure(service_class, pvp_season_id, error)
        Rails.logger.error(
          "[BuildAggregationsJob] #{service_class} failed for season #{pvp_season_id}: #{error}"
        )
        Pvp::SyncLogger.error("#{service_class} failed for season #{pvp_season_id}: #{error}")
      end

      def log_completion(pvp_season_id, results)
        Rails.logger.info(
          "[BuildAggregationsJob] Season #{pvp_season_id} done — " \
            "items: #{results[:items]}, enchants: #{results[:enchants]}, " \
            "gems: #{results[:gems]}, talents: #{results[:talents]}"
        )
      end

      def sync_log_completion(results)
        Pvp::SyncLogger.aggregations_complete(
          items:    results[:items],
          enchants: results[:enchants],
          gems:     results[:gems],
          talents:  results[:talents]
        )
      end

      def clear_meta_cache
        Rails.cache.increment(Api::V1::BaseController::META_CACHE_VERSION_KEY)
        Rails.logger.info("[BuildAggregationsJob] Meta cache version bumped")
      end

      def end_cycle_if_needed(sync_cycle_id, cycle_started_at)
        return unless sync_cycle_id

        elapsed = compute_elapsed_seconds(cycle_started_at)
        Pvp::SyncLogger.end_cycle(cycle_id: sync_cycle_id, elapsed_seconds: elapsed)
      end

      def compute_elapsed_seconds(cycle_started_at)
        return nil unless cycle_started_at

        Time.current - Time.zone.parse(cycle_started_at)
      end
  end
end
