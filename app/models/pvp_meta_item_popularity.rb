# == Schema Information
#
# Table name: pvp_meta_item_popularity
# Database name: primary
#
#  id            :bigint           not null, primary key
#  bracket       :string           not null
#  slot          :string           not null
#  snapshot_at   :datetime         not null
#  usage_count   :integer          default(0), not null
#  usage_pct     :decimal(5, 2)
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  item_id       :bigint           not null
#  pvp_season_id :bigint           not null
#  spec_id       :integer          not null
#
# Indexes
#
#  idx_meta_item_lookup                             (pvp_season_id,bracket,spec_id,slot)
#  idx_meta_item_unique                             (pvp_season_id,bracket,spec_id,slot,item_id) UNIQUE
#  index_pvp_meta_item_popularity_on_item_id        (item_id)
#  index_pvp_meta_item_popularity_on_pvp_season_id  (pvp_season_id)
#
# Foreign Keys
#
#  fk_rails_...  (item_id => items.id)
#  fk_rails_...  (pvp_season_id => pvp_seasons.id)
#
class PvpMetaItemPopularity < ApplicationRecord
  self.table_name = "pvp_meta_item_popularity"

  belongs_to :pvp_season
  belongs_to :item
end
