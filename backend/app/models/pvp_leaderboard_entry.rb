# == Schema Information
#
# Table name: pvp_leaderboard_entries
# Database name: primary
#
#  id                          :bigint           not null, primary key
#  equipment_processed_at      :datetime
#  hero_talent_tree_name       :string
#  item_level                  :integer
#  losses                      :integer
#  rank                        :integer
#  rating                      :integer
#  raw_equipment               :jsonb
#  raw_specialization          :jsonb
#  snapshot_at                 :datetime
#  spec                        :string
#  specialization_processed_at :datetime
#  tier_4p_active              :boolean          default(FALSE)
#  tier_set_name               :string
#  tier_set_pieces             :integer
#  wins                        :integer
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  character_id                :bigint           not null
#  class_id                    :integer
#  hero_talent_tree_id         :integer
#  pvp_leaderboard_id          :bigint           not null
#  spec_id                     :integer
#  tier_set_id                 :integer
#
# Indexes
#
#  index_pvp_leaderboard_entries_on_character_id         (character_id)
#  index_pvp_leaderboard_entries_on_hero_talent_tree_id  (hero_talent_tree_id)
#  index_pvp_leaderboard_entries_on_pvp_leaderboard_id   (pvp_leaderboard_id)
#  index_pvp_leaderboard_entries_on_rank                 (rank)
#  index_pvp_leaderboard_entries_on_tier_set_id          (tier_set_id)
#
# Foreign Keys
#
#  fk_rails_...  (character_id => characters.id)
#  fk_rails_...  (pvp_leaderboard_id => pvp_leaderboards.id)
#
class PvpLeaderboardEntry < ApplicationRecord
  include Translatable

  belongs_to :pvp_leaderboard
  belongs_to :character

  self.filter_attributes += %i[
    raw_equipment raw_specialization
  ]
end
