# == Schema Information
#
# Table name: pvp_leaderboard_entries
# Database name: primary
#
#  id                          :bigint           not null, primary key
#  equipment_processed_at      :datetime
#  hero_talent_tree_name       :string
#  item_level                  :integer
#  losses                      :integer          default(0)
#  rank                        :integer
#  rating                      :integer
#  raw_equipment               :binary
#  raw_specialization          :binary
#  snapshot_at                 :datetime
#  specialization_processed_at :datetime
#  tier_4p_active              :boolean          default(FALSE)
#  tier_set_name               :string
#  tier_set_pieces             :integer
#  wins                        :integer          default(0)
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  character_id                :bigint           not null
#  hero_talent_tree_id         :integer
#  pvp_leaderboard_id          :bigint           not null
#  spec_id                     :integer
#  tier_set_id                 :integer
#
# Indexes
#
#  index_entries_for_batch_processing                      (id,equipment_processed_at)
#  index_entries_for_spec_meta                             (pvp_leaderboard_id,spec_id,rating)
#  index_entries_on_leaderboard_and_rating                 (pvp_leaderboard_id,rating)
#  index_entries_on_leaderboard_and_snapshot               (pvp_leaderboard_id,snapshot_at)
#  index_pvp_entries_on_character_and_equipment_processed  (character_id,equipment_processed_at) WHERE (equipment_processed_at IS NOT NULL)
#  index_pvp_entries_on_character_and_snapshot             (character_id,snapshot_at)
#  index_pvp_entries_on_snapshot_at                        (snapshot_at)
#  index_pvp_leaderboard_entries_on_character_id           (character_id)
#  index_pvp_leaderboard_entries_on_hero_talent_tree_id    (hero_talent_tree_id)
#  index_pvp_leaderboard_entries_on_pvp_leaderboard_id     (pvp_leaderboard_id)
#  index_pvp_leaderboard_entries_on_rank                   (rank)
#  index_pvp_leaderboard_entries_on_tier_set_id            (tier_set_id)
#
# Foreign Keys
#
#  fk_rails_...  (character_id => characters.id)
#  fk_rails_...  (pvp_leaderboard_id => pvp_leaderboards.id)
#
class PvpLeaderboardEntry < ApplicationRecord
  include Translatable
  include CompressedJson

  compressed_json :raw_equipment, :raw_specialization

  belongs_to :pvp_leaderboard
  belongs_to :character

  scope :latest_snapshot_for_bracket, ->(bracket, season_id: nil) {
    season_filter =
      if season_id.present?
        season_id
      else
        PvpSeason.where(is_current: true).select(:id).limit(1)
      end

    leaderboard_ids = PvpLeaderboard
      .where(bracket: bracket)
      .where(pvp_season_id: season_filter)
      .select(:id)

    # Use the latest snapshot that has at least one processed entry (spec_id set).
    # Falls back to previous snapshot when the current sync is still in progress or failed.
    latest_processed = PvpLeaderboardEntry
      .where(pvp_leaderboard_id: leaderboard_ids)
      .where.not(spec_id: nil)
      .select("MAX(pvp_leaderboard_entries.snapshot_at)")

    joins(pvp_leaderboard: :pvp_season)
      .where(pvp_leaderboards: { bracket: bracket })
      .where(pvp_seasons: { id: season_filter })
      .where("pvp_leaderboard_entries.snapshot_at = (#{latest_processed.to_sql})")
  }

  has_many :pvp_leaderboard_entry_items, dependent: :destroy
  has_many :items, through: :pvp_leaderboard_entry_items

  self.filter_attributes += %i[
    raw_equipment raw_specialization
  ]

  def winrate
    total_games = wins.to_i + losses.to_i
    return 0.0 if total_games.zero?

    (wins.to_f / total_games) * 100
  end
end
