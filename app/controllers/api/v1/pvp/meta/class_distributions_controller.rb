module Api
  module V1
    module Pvp
      module Meta
        class ClassDistributionsController < BaseController
          # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          def show
            season  = PvpSeason.find_by!(blizzard_id: params.fetch(:season_id).to_i)
            bracket = params.fetch(:bracket)
            region  = params.fetch(:region, "us")
            role    = params[:role] || :dps

            cache_key = meta_cache_key("class_distribution", season.blizzard_id, bracket, region, role)

            json = Rails.cache.fetch(cache_key, expires_in: META_CACHE_TTL) do
              distribution = ::Pvp::Meta::ClassDistributionService.new(
                role:    role,
                season:  season,
                bracket: bracket,
                region:  region,
              ).call

              {
                season_id:     season.blizzard_id,
                bracket:       bracket,
                region:        region,
                total_entries: distribution.sum { |row| row[:count] },
                classes:       distribution
              }
            end

            render json: json
            set_cache_headers
          end
          # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
        end
      end
    end
  end
end
