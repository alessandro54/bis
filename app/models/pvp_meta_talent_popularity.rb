class PvpMetaTalentPopularity < ApplicationRecord
  self.table_name = "pvp_meta_talent_popularity"

  belongs_to :pvp_season
  belongs_to :talent
end
