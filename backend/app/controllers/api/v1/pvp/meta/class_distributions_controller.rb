# app/services/pvp/meta/class_distribution.rb
module Api
  module V1
    module Pvp
      module Meta
        class ClassDistributionsController < BaseController
          def show
            season  = PvpSeason.find_by!(blizzard_id: params.fetch(:season_id).to_i)
            bracket = params.fetch(:bracket)
            region  = params.fetch(:region, "us")

            distribution = ::Pvp::Meta::ClassDistributionService.new(
              role:   params[:role],
              season:  season,
              bracket: bracket,
              region:  region,
            ).call

            render json: {
              season_id:     season.blizzard_id,
              bracket:       bracket,
              region:        region,
              total_entries: distribution.sum { |row| row[:count] },
              classes:       distribution
            }
          end
        end
      end
    end
  end
end
