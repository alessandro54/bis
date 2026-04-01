module Blizzard
  module Data
    module PvpSeasons
      class SyncCurrentSeasonService < ApplicationService
        def call
          current_season_id = get_current_season_id

          return failure("No current season found in Blizzard API response") unless current_season_id

          show_response = Blizzard::Api::GameData::PvpSeason::Show.fetch(pvp_season_id: current_season_id)

          season = set_season(show_response)

          unless season.is_current
            PvpSeason.where(is_current: true).where.not(blizzard_id: current_season_id)
                     .update_all(is_current: false) # rubocop:disable Rails/SkipsModelValidations
            season.is_current = true
          end

          season.save!

          Rails.cache.delete("pvp_season/current")

          Rails.logger.info(
            "[SyncCurrentSeasonService] Current season: #{current_season_id} (#{display_name}), " \
            "record id=#{season.id}"
          )

          success(season)
        rescue Blizzard::Client::Error => e
          failure(e)
        end

        private

          def parse_timestamp(ms)
            return nil unless ms

            Time.zone.at(ms / 1000)
          end

          def get_current_season_id
            index_response = Blizzard::Api::GameData::PvpSeason::SeasonsIndex.fetch
            index_response.dig("current_season", "id")
          end

          def set_season(season_response)
            display_name = season_response["season_name"] || "PvP Season #{current_season_id}"
            start_time   = parse_timestamp(season_response["season_start_timestamp"])
            end_time     = parse_timestamp(season_response["season_end_timestamp"])

            season = PvpSeason.find_or_initialize_by(blizzard_id: current_season_id)
            season.display_name = display_name
            season.start_time   = start_time if start_time
            season.end_time     = end_time   if end_time

            season
          end
      end
    end
  end
end
