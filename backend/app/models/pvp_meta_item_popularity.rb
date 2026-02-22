class PvpMetaItemPopularity < ApplicationRecord
  self.table_name = "pvp_meta_item_popularity"

  belongs_to :pvp_season
  belongs_to :item
end
