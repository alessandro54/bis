module Pvp
  class BuildAggregationsJob < ApplicationJob
    queue_as :default

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def perform(sync_cycle_id:)
      cycle = PvpSyncCycle.find(sync_cycle_id)
      season = cycle.pvp_season
      snapshot_at = cycle.snapshot_at

      cycle.update!(status: :aggregating)

      # Get all unique brackets across all regions for this season
      brackets = PvpLeaderboard
        .where(pvp_season_id: season.id)
        .distinct
        .pluck(:bracket)

      # Delete old aggregation rows for this season
      PvpMetaTalentBuild.where(pvp_season_id: season.id).delete_all
      PvpMetaTalentPick.where(pvp_season_id: season.id).delete_all
      PvpMetaHeroTree.where(pvp_season_id: season.id).delete_all
      PvpMetaItemPopularity.where(pvp_season_id: season.id).delete_all

      # For each bracket: run both aggregation services (they aggregate globally across all regions)
      brackets.each do |bracket|
        talent_result = Pvp::Meta::TalentAggregationService.call(
          season:      season,
          bracket:     bracket,
          snapshot_at: snapshot_at
        )

        unless talent_result.success?
          Rails.logger.error(
            "[BuildAggregationsJob] Talent aggregation failed for #{bracket}: #{talent_result.error}"
          )
        end

        item_result = Pvp::Meta::ItemAggregationService.call(
          season:      season,
          bracket:     bracket,
          snapshot_at: snapshot_at
        )

        unless item_result.success?
          Rails.logger.error(
            "[BuildAggregationsJob] Item aggregation failed for #{bracket}: #{item_result.error}"
          )
        end
      end

      cycle.update!(status: :completed, completed_at: Time.current)

      Rails.logger.info(
        "[BuildAggregationsJob] Completed aggregations for season #{season.id}: " \
        "#{brackets.size} brackets, " \
        "#{PvpMetaTalentBuild.where(pvp_season_id: season.id).count} talent builds, " \
        "#{PvpMetaTalentPick.where(pvp_season_id: season.id).count} talent picks, " \
        "#{PvpMetaHeroTree.where(pvp_season_id: season.id).count} hero trees, " \
        "#{PvpMetaItemPopularity.where(pvp_season_id: season.id).count} item popularity records"
      )
    rescue => e
      cycle&.update!(status: :failed) if cycle&.persisted?
      raise
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
  end
end
