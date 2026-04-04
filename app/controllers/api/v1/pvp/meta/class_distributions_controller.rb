module Api
  module V1
    module Pvp
      module Meta
        class ClassDistributionsController < BaseController
          # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Layout/LineLength
          def show
            season  = params[:season_id].present? ? PvpSeason.find_by!(blizzard_id: params[:season_id].to_i) : current_season
            bracket = params.fetch(:bracket)
            region  = params.fetch(:region, "all")
            region  = nil if region == "all"
            role    = params[:role] || :dps

            model = params[:new_model] == "true" ? :bayesian : :legacy
            cache_key = meta_cache_key("class_distribution", model, season.blizzard_id, bracket, region, role)

            json = meta_cache_fetch(cache_key) do
              service_class = model == :bayesian ?
                ::Pvp::Meta::BayesianClassDistributionService :
                ::Pvp::Meta::ClassDistributionService

              distribution = service_class.new(
                role:    role,
                season:  season,
                bracket: bracket,
                region:  region,
              ).call

              {
                season_id:     season.blizzard_id,
                bracket:       bracket,
                region:        region || "all",
                total_entries: distribution.sum { |row| row[:count] },
                classes:       distribution
              }
            end

            render json: json
            set_cache_headers
          end
          # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Layout/LineLength
        end
      end
    end
  end
end
