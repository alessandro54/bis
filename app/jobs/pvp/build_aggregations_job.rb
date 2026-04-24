module Pvp
  class BuildAggregationsJob < ApplicationJob
    queue_as :default

    def perform(pvp_season_id:, sync_cycle_id: nil, cycle_started_at: nil)
      Pvp::BuildAggregationsService.call(
        pvp_season_id:    pvp_season_id,
        sync_cycle_id:    sync_cycle_id,
        cycle_started_at: cycle_started_at
      )
    end
  end
end
