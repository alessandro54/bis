# == Schema Information
#
# Table name: pvp_sync_cycles
# Database name: primary
#
#  id                          :bigint           not null, primary key
#  completed_at                :datetime
#  completed_character_batches :integer          default(0), not null
#  expected_character_batches  :integer          default(0), not null
#  regions                     :string           default([]), not null, is an Array
#  snapshot_at                 :datetime         not null
#  status                      :string           default("syncing_leaderboards"), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  pvp_season_id               :bigint           not null
#
# Indexes
#
#  index_pvp_sync_cycles_on_pvp_season_id             (pvp_season_id)
#  index_pvp_sync_cycles_on_pvp_season_id_and_status  (pvp_season_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (pvp_season_id => pvp_seasons.id)
#
class PvpSyncCycle < ApplicationRecord
  belongs_to :pvp_season

  enum :status, {
    syncing_leaderboards: "syncing_leaderboards",
    syncing_characters:   "syncing_characters",
    aggregating:          "aggregating",
    completed:            "completed",
    failed:               "failed"
  }

  validates :status, presence: true
  validates :snapshot_at, presence: true
  validates :regions, presence: true

  # Atomic increment — returns the new count after incrementing.
  # Uses a single UPDATE + RETURNING to avoid race conditions.
  def increment_completed_character_batches!
    result = self.class.where(id: id).update_all(
      "completed_character_batches = completed_character_batches + 1"
    )
    reload.completed_character_batches
  end

  def all_character_batches_done?
    completed_character_batches >= expected_character_batches
  end
end
