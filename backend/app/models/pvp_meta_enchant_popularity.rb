class PvpMetaEnchantPopularity < ApplicationRecord
  self.table_name = "pvp_meta_enchant_popularity"

  belongs_to :pvp_season
  belongs_to :enchantment
end
