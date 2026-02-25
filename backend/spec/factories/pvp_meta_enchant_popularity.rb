# == Schema Information
#
# Table name: pvp_meta_enchant_popularity
#
FactoryBot.define do
  factory :pvp_meta_enchant_popularity do
    pvp_season
    enchantment
    bracket { "3v3" }
    spec_id { 62 } # Arcane Mage
    slot { "main_hand" }
    usage_count { Faker::Number.between(from: 1, to: 100) }
    usage_pct { Faker::Number.between(from: 1.0, to: 100.0).round(2) }
    snapshot_at { Time.current }
  end
end

