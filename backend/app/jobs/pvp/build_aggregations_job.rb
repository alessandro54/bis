module Pvp
  class BuildAggregationsJob < ApplicationJob
    queue_as :default

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

      def aggregations
        [
          [ :items,    Pvp::Meta::ItemAggregationService ],
          [ :enchants, Pvp::Meta::EnchantAggregationService ],
          [ :gems,     Pvp::Meta::GemAggregationService ]
        ]
      end

      def run_aggregations(season, pvp_season_id)
        results = run_with_threads(aggregations, concurrency: aggregations.size) do |(key, service_class)|
          run_single_aggregation(key, service_class, season, pvp_season_id)
        end

        results.to_h
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
            "items: #{results[:items]}, enchants: #{results[:enchants]}, gems: #{results[:gems]}"
        )
      end

      def sync_log_completion(results)
        Pvp::SyncLogger.aggregations_complete(
          items:    results[:items],
          enchants: results[:enchants],
          gems:     results[:gems]
        )
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
