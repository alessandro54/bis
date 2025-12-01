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
            limit   = params.fetch(:limit, 200).to_i

            distribution = ::Pvp::Meta::ClassDistributionService.new(
              season:  season,
              bracket: bracket,
              region:  region,
              limit:   limit
            ).call

            render json: {
              season_id:     season.blizzard_id,
              bracket:       bracket,
              region:        region,
              limit:         limit,
              total_entries: distribution.sum { |row| row[:count] },
              classes:       distribution
            }
          end
        end
      end
    end
  end
end
