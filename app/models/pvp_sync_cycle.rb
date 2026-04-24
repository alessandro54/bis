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
    failed:               "failed",
    aborted:              "aborted"
  }

  def self.active
    where(status: %i[syncing_leaderboards syncing_characters]).order(created_at: :desc).first
  end

  validates :status, presence: true
  validates :snapshot_at, presence: true
  validates :regions, presence: true

  # Atomic increment via UPDATE...RETURNING — one round-trip instead of two.
  # Also updates the in-memory attribute so callers can immediately check
  # all_*_done? without a stale value causing the final job to be missed.
  PROGRESS_MILESTONES = [ 25, 50, 75 ].freeze

  def increment_completed_character_batches!
    result = self.class.connection.exec_query(
      "UPDATE pvp_sync_cycles SET completed_character_batches = completed_character_batches + 1 " \
      "WHERE id = $1 RETURNING completed_character_batches",
      "IncrCharacterBatches",
      [ id ]
    )
    self.completed_character_batches = result.rows.first.first.to_i
    notify_progress_milestone!
  end

  def all_character_batches_done?
    completed_character_batches >= expected_character_batches
  end

  def progress_pct
    return 0 if expected_character_batches.zero?

    (completed_character_batches.to_f / expected_character_batches * 100).round(1)
  end

  def eta_seconds
    return nil if completed_character_batches.zero?

    remaining = expected_character_batches - completed_character_batches
    return nil if remaining <= 0
    return nil if remaining.to_f / expected_character_batches < 0.02

    elapsed = Time.current - created_at
    (elapsed / completed_character_batches) * remaining
  end

  private

    def notify_progress_milestone!
      return if expected_character_batches.zero?

      milestone = crossed_milestone
      return unless milestone

      Pvp::NotifyCycleProgressJob.perform_later(
        id,
        milestone,
        completed_batches: completed_character_batches,
        expected_batches:  expected_character_batches,
        elapsed_seconds:   (Time.current - created_at).round,
        eta_seconds_snap:  eta_seconds&.round
      )
    end

    def crossed_milestone
      pct      = (completed_character_batches.to_f / expected_character_batches * 100).floor
      prev_pct = ((completed_character_batches - 1).to_f / expected_character_batches * 100).floor
      PROGRESS_MILESTONES.find { |m| prev_pct < m && pct >= m }
    end
end
