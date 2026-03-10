module Pvp
  class BuildAggregationsJob < ApplicationJob
    queue_as :default

    # Each entry: [key, service_class, model_class, min_interval]
    # min_interval — skip if the latest snapshot_at for the season is more recent than this.
    AGGREGATIONS = [
      [ :items,    Pvp::Meta::ItemAggregationService,    PvpMetaItemPopularity,    1.hour    ],
      [ :enchants, Pvp::Meta::EnchantAggregationService, PvpMetaEnchantPopularity, 1.hour    ],
      [ :gems,     Pvp::Meta::GemAggregationService,     PvpMetaGemPopularity,     1.hour    ],
      [ :talents,  Pvp::Meta::TalentAggregationService,  PvpMetaTalentPopularity,  6.hours   ]
    ].freeze

    def perform(pvp_season_id:, sync_cycle_id: nil, cycle_started_at: nil)
      season = find_season!(pvp_season_id)
      return unless season

      results = run_aggregations(season, pvp_season_id)

      log_completion(pvp_season_id, results)
      sync_log_completion(results)

      end_cycle_if_needed(sync_cycle_id, cycle_started_at)
    end

    private

      def find_season!(pvp_season_id)
        season = PvpSeason.find_by(id: pvp_season_id)
        return season if season

        Rails.logger.warn("[BuildAggregationsJob] Season #{pvp_season_id} not found, skipping")
        nil
      end

      def run_aggregations(season, pvp_season_id)
        results = run_with_threads(AGGREGATIONS, concurrency: AGGREGATIONS.size) do |tuple|
          key, service_class, model_class, min_interval = tuple
          if stale?(model_class, season, min_interval)
            run_single_aggregation(key, service_class, season, pvp_season_id)
          else
            [ key, :skipped ]
          end
        end

        results.to_h
      end

      def stale?(model_class, season, min_interval)
        last = model_class.where(pvp_season_id: season.id).maximum(:snapshot_at)
        last.nil? || last < min_interval.ago
      end

      def run_single_aggregation(key, service_class, season, pvp_season_id)
        result = service_class.call(season: season)

        if result.success?
          [ key, result.context[:count] ]
        else
          log_aggregation_failure(service_class, pvp_season_id, result.error)
          [ key, :failed ]
        end
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

        clear_meta_cache
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
