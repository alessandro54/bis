class PvpMetaGemPopularity < ApplicationRecord
  self.table_name = "pvp_meta_gem_popularity"

  belongs_to :pvp_season
  belongs_to :item
end
