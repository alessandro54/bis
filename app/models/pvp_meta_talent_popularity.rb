# == Schema Information
#
# Table name: pvp_meta_talent_popularity
# Database name: primary
#
#  id            :bigint           not null, primary key
#  bracket       :string           not null
#  in_top_build  :boolean          default(FALSE), not null
#  snapshot_at   :datetime         not null
#  talent_type   :string           not null
#  usage_count   :integer          default(0), not null
#  usage_pct     :decimal(8, 4)
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  pvp_season_id :bigint           not null
#  spec_id       :integer          not null
#  talent_id     :bigint           not null
#
# Indexes
#
#  idx_meta_talent_lookup                             (pvp_season_id,bracket,spec_id,talent_type)
#  idx_meta_talent_unique                             (pvp_season_id,bracket,spec_id,talent_id) UNIQUE
#  index_pvp_meta_talent_popularity_on_pvp_season_id  (pvp_season_id)
#  index_pvp_meta_talent_popularity_on_talent_id      (talent_id)
#
# Foreign Keys
#
#  fk_rails_...  (pvp_season_id => pvp_seasons.id)
#  fk_rails_...  (talent_id => talents.id)
#
class PvpMetaTalentPopularity < ApplicationRecord
  self.table_name = "pvp_meta_talent_popularity"

  belongs_to :pvp_season
  belongs_to :talent
end
