FactoryBot.define do
  factory :pvp_leaderboard do
    association :pvp_season
    region  { "us" }
    bracket { "2v2" }
  end
end