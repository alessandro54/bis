# == Schema Information
#
# Table name: pvp_meta_hero_trees
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  avg_rating            :decimal(7, 2)
#  avg_winrate           :decimal(5, 4)
#  bracket               :string           not null
#  hero_talent_tree_name :string
#  snapshot_at           :datetime         not null
#  usage_count           :integer          default(0), not null
#  usage_pct             :decimal(5, 2)
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  hero_talent_tree_id   :integer          not null
#  pvp_season_id         :bigint           not null
#  spec_id               :integer          not null
#
# Indexes
#
#  idx_hero_trees_lookup                       (pvp_season_id,bracket,spec_id)
#  index_pvp_meta_hero_trees_on_pvp_season_id  (pvp_season_id)
#
# Foreign Keys
#
#  fk_rails_...  (pvp_season_id => pvp_seasons.id)
#
class PvpMetaHeroTree < ApplicationRecord
  belongs_to :pvp_season
end
