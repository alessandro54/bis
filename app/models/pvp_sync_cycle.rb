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
    completed:            "completed",
    failed:               "failed"
  }

  validates :status, presence: true
  validates :snapshot_at, presence: true
  validates :regions, presence: true

  # Atomic increment via UPDATE...RETURNING — one round-trip instead of two.
  # Also updates the in-memory attribute so callers can immediately check
  # all_*_done? without a stale value causing the final job to be missed.
  def increment_completed_character_batches!
    result = self.class.connection.exec_query(
      "UPDATE pvp_sync_cycles SET completed_character_batches = completed_character_batches + 1 " \
      "WHERE id = $1 RETURNING completed_character_batches",
      "IncrCharacterBatches",
      [ id ]
    )
    self.completed_character_batches = result.rows.first.first.to_i
  end

  def all_character_batches_done?
    completed_character_batches >= expected_character_batches
  end
end
