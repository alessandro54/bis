# == Schema Information
#
# Table name: pvp_seasons
# Database name: primary
#
#  id           :bigint           not null, primary key
#  display_name :string
#  end_time     :datetime
#  is_current   :boolean          default(FALSE)
#  start_time   :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  blizzard_id  :integer
#
# Indexes
#
#  index_pvp_seasons_on_blizzard_id  (blizzard_id) UNIQUE
#  index_pvp_seasons_on_is_current   (is_current)
#  index_pvp_seasons_on_updated_at   (updated_at)
#
class PvpSeason < ApplicationRecord
  has_many :pvp_leaderboards, dependent: :destroy

  validates :display_name, presence: true
  validates :blizzard_id, presence: true, uniqueness: true
  validates :blizzard_id, numericality: { only_integer: true }

  def self.current
    find_by(is_current: true) || order(blizzard_id: :desc).first
  end
end
