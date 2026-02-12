class PvpMetaItemPopularity < ApplicationRecord
  belongs_to :pvp_season
  belongs_to :item
end
