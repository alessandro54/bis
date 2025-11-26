# spec/factories/pvp_leaderboard_entries.rb
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
#  raw_equipment               :jsonb
#  raw_specialization          :jsonb
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
#  index_pvp_leaderboard_entries_on_character_id         (character_id)
#  index_pvp_leaderboard_entries_on_hero_talent_tree_id  (hero_talent_tree_id)
#  index_pvp_leaderboard_entries_on_pvp_leaderboard_id   (pvp_leaderboard_id)
#  index_pvp_leaderboard_entries_on_rank                 (rank)
#  index_pvp_leaderboard_entries_on_tier_set_id          (tier_set_id)
#
# Foreign Keys
#
#  fk_rails_...  (character_id => characters.id)
#  fk_rails_...  (pvp_leaderboard_id => pvp_leaderboards.id)
#
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

    spec_id { Faker::Number.between(from: 1, to: 50) }

    hero_talent_tree_id   { Faker::Number.between(from: 1, to: 20) }
    hero_talent_tree_name { Faker::Games::DnD.klass.downcase }

    tier_set_id           { Faker::Number.between(from: 1, to: 20) }
    tier_set_name         { "Set #{tier_set_id}" }
    tier_set_pieces       { Faker::Number.between(from: 0, to: 4) }
    tier_4p_active        { tier_set_pieces >= 4 }

    trait :with_gear do
      index = (1..3).to_a.sample
      raw_equipment do
        JSON.parse(
          File.read(
            Rails.root.join("spec/fixtures/pvp_leaderboard_entries/gear_raw_#{index}.json")
          )
        )
      end

      raw_specialization do
        JSON.parse(
          File.read(
            Rails.root.join("spec/fixtures/pvp_leaderboard_entries/talents_raw_#{index}.json")
          )
        )
      end
    end
  end
end
