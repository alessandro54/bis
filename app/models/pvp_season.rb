# == Schema Information
#
# Table name: pvp_seasons
# Database name: primary
#
#  id                     :bigint           not null, primary key
#  display_name           :string
#  end_time               :datetime
#  is_current             :boolean          default(FALSE)
#  start_time             :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  blizzard_id            :integer
#  live_pvp_sync_cycle_id :bigint
#
# Indexes
#
#  index_pvp_seasons_on_blizzard_id             (blizzard_id) UNIQUE
#  index_pvp_seasons_on_is_current              (is_current)
#  index_pvp_seasons_on_live_pvp_sync_cycle_id  (live_pvp_sync_cycle_id)
#  index_pvp_seasons_on_updated_at              (updated_at)
#
# Foreign Keys
#
#  fk_rails_...  (live_pvp_sync_cycle_id => pvp_sync_cycles.id)
#
class PvpSeason < ApplicationRecord
  has_many :pvp_leaderboards, dependent: :destroy
  belongs_to :live_pvp_sync_cycle, class_name: "PvpSyncCycle", optional: true

  validates :display_name, presence: true
  validates :blizzard_id, presence: true, uniqueness: true
  validates :blizzard_id, numericality: { only_integer: true }

  def self.current
    Rails.cache.fetch("pvp_season/current", expires_in: 1.hour) do
      find_by(is_current: true) || order(blizzard_id: :desc).first
    end
  end
end
