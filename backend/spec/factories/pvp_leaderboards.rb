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
#  index_pvp_leaderboards_on_pvp_season_id              (pvp_season_id)
#  index_pvp_leaderboards_on_pvp_season_id_and_bracket  (pvp_season_id,bracket) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (pvp_season_id => pvp_seasons.id)
#
FactoryBot.define do
  factory :pvp_leaderboard do
    association :pvp_season
    region  { %w[us eu kr tw].sample }
    bracket { %w[2v2 3v3 rbg deathknight-suffle].sample }
    last_synced_at { Time.current }
  end
end
