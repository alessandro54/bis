# == Schema Information
#
# Table name: pvp_leaderboards
# Database name: primary
#
#  id             :bigint           not null, primary key
#  bracket        :string
#  last_synced_at :datetime
#  region         :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  pvp_season_id  :bigint           not null
#
# Indexes
#
#  idx_leaderboards_season_bracket_region   (pvp_season_id,bracket,region) UNIQUE
#  index_pvp_leaderboards_on_pvp_season_id  (pvp_season_id)
#
# Foreign Keys
#
#  fk_rails_...  (pvp_season_id => pvp_seasons.id)
#
class PvpLeaderboard < ApplicationRecord
  belongs_to :pvp_season

  has_many :entries, class_name: "PvpLeaderboardEntry", dependent: :destroy
end
