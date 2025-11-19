# == Schema Information
#
# Table name: pvp_leaderboard_entries
#
#  id                 :bigint           not null, primary key
#  gear_raw           :jsonb
#  item_level         :integer
#  losses             :integer
#  rank               :integer
#  rating             :integer
#  snapshot_at        :datetime
#  spec               :string
#  talents_raw        :jsonb
#  wins               :integer
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  character_id       :bigint           not null
#  class_id           :integer
#  pvp_leaderboard_id :bigint           not null
#  spec_id            :integer
#
# Indexes
#
#  index_pvp_leaderboard_entries_on_character_id        (character_id)
#  index_pvp_leaderboard_entries_on_pvp_leaderboard_id  (pvp_leaderboard_id)
#  index_pvp_leaderboard_entries_on_rank                (rank)
#
# Foreign Keys
#
#  fk_rails_...  (character_id => characters.id)
#  fk_rails_...  (pvp_leaderboard_id => pvp_leaderboards.id)
#
class PvpLeaderboardEntry < ApplicationRecord
  belongs_to :pvp_leaderboard
  belongs_to :character
end
