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

  # Aggregate slugs used by the API/UI. Each one fans out to its per-spec
  # leaderboards via the LIKE pattern; no standalone leaderboard is stored
  # under these keys (sync skips Blizzard's "*-overall" buckets entirely).
  OVERALL_BRACKETS = {
    "blitz" => "blitz-%",
    "shuffle" => "shuffle-%"
  }.freeze

  # Resolves any aggregate slug to its per-spec bracket pattern, or matches
  # a single bracket exactly when no aggregation is needed.
  scope :for_bracket, ->(bracket) {
    pattern = OVERALL_BRACKETS[bracket]
    pattern ? where("bracket LIKE ?", pattern) : where(bracket: bracket)
  }

  def get_top_n(n, spec_id: nil)
    scope = entries
    scope = scope.where(spec_id: spec_id) if spec_id.present?
    scope.order(rank: :asc).limit(n)
  end
end
