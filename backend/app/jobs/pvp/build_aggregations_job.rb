module Pvp
  class BuildAggregationsJob < ApplicationJob
    queue_as :default

    def perform(pvp_season_id:, sync_cycle_id: nil, cycle_started_at: nil)
      season = PvpSeason.find_by(id: pvp_season_id)
      unless season
        Rails.logger.warn("[BuildAggregationsJob] Season #{pvp_season_id} not found, skipping")
        return
      end

      results = {}

      [
        [ :items,    Pvp::Meta::ItemAggregationService ],
        [ :enchants, Pvp::Meta::EnchantAggregationService ],
        [ :gems,     Pvp::Meta::GemAggregationService ]
      ].each do |key, service_class|
        result = service_class.call(season: season)

        if result.success?
          results[key] = result.context[:count]
        else
          Rails.logger.error(
            "[BuildAggregationsJob] #{service_class} failed for season #{pvp_season_id}: #{result.error}"
          )
          Pvp::SyncLogger.error("#{service_class} failed for season #{pvp_season_id}: #{result.error}")
          results[key] = :failed
        end
      end

      Rails.logger.info(
        "[BuildAggregationsJob] Season #{pvp_season_id} done — " \
        "items: #{results[:items]}, enchants: #{results[:enchants]}, gems: #{results[:gems]}"
      )

      Pvp::SyncLogger.aggregations_complete(
        items:    results[:items],
        enchants: results[:enchants],
        gems:     results[:gems]
      )

      if sync_cycle_id
        elapsed = cycle_started_at ? Time.current - Time.parse(cycle_started_at) : nil
        Pvp::SyncLogger.end_cycle(cycle_id: sync_cycle_id, elapsed_seconds: elapsed)
      end
    end
  end
end
