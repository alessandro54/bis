module Pvp
  class BuildAggregationsJob < ApplicationJob
    queue_as :default

    def perform(pvp_season_id:)
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
          results[key] = :failed
        end
      end

      Rails.logger.info(
        "[BuildAggregationsJob] Season #{pvp_season_id} done — " \
        "items: #{results[:items]}, enchants: #{results[:enchants]}, gems: #{results[:gems]}"
      )
    end
  end
end
