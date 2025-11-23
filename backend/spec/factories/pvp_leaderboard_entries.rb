# spec/factories/pvp_leaderboard_entries.rb
FactoryBot.define do
  factory :pvp_leaderboard_entry do
    association :pvp_leaderboard
    association :character

    rank      { Faker::Number.between(from: 1, to: 3000) }
    rating    { Faker::Number.between(from: 1200, to: 3500) }
    wins      { Faker::Number.between(from: 0, to: 500) }
    losses    { Faker::Number.between(from: 0, to: 500) }
    snapshot_at { Time.current }

    item_level { Faker::Number.between(from: 450, to: 700) }

    class_id { Faker::Number.between(from: 1, to: 13) }
    spec_id  { Faker::Number.between(from: 1, to: 50) }

    hero_talent_tree_id   { Faker::Number.between(from: 1, to: 20) }
    hero_talent_tree_name { "Fatebound" }

    tier_set_id           { Faker::Number.between(from: 1, to: 20) }
    tier_set_name         { "Set #{tier_set_id}" }
    tier_set_pieces       { Faker::Number.between(from: 0, to: 4) }
    tier_4p_active        { tier_set_pieces >= 4 }

    gear_raw     { [] }
    talents_raw  { {} }
  end
end