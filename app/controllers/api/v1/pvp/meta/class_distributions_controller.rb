module Api
  module V1
    module Pvp
      module Meta
        class ClassDistributionsController < BaseController
          before_action :validate_show_params!, only: :show

          def show
            season, bracket, region, role, model = parse_distribution_params
            cache_key = meta_cache_key("class_distribution", model, season.blizzard_id, bracket, region, role)
            json = meta_cache_fetch(cache_key) do
              build_distribution_response(season, bracket, region, role, model)
            end
            render json: json
            set_cache_headers
          end

          private

            def parse_distribution_params
              season = fetch_season
              bracket = params.fetch(:bracket)
              region = params.fetch(:region, "all")
              region = validate_region(region == "all" ? nil : region)
              role = params.fetch(:role, "dps")
              role = role == "all" ? nil : validate_role(role)
              model = params[:new_model] == "true" ? :bayesian : :legacy
              [ season, bracket, region, role, model ]
            end

            def fetch_season
              return PvpSeason.find_by!(blizzard_id: params[:season_id].to_i) if params[:season_id].present?

              current_season
            end

            def build_distribution_response(season, bracket, region, role, model)
              service_class = model == :bayesian ?
                ::Pvp::Meta::BayesianClassDistributionService :
                ::Pvp::Meta::ClassDistributionService
              distribution = service_class.new(role:, season:, bracket:, region:).call
              {
                season_id:     season.blizzard_id,
                bracket:,
                region:        region || "all",
                total_entries: distribution.sum { |row| row[:count] },
                classes:       distribution
              }
            end

            def validate_show_params!
              validate_bracket!(params.fetch(:bracket)) or return
            end
        end
      end
    end
  end
end
