# == Schema Information
#
# Table name: pvp_meta_enchant_popularity
# Database name: primary
#
#  id             :bigint           not null, primary key
#  bracket        :string           not null
#  slot           :string           not null
#  snapshot_at    :datetime         not null
#  usage_count    :integer          default(0), not null
#  usage_pct      :decimal(5, 2)
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  enchantment_id :bigint           not null
#  pvp_season_id  :bigint           not null
#  spec_id        :integer          not null
#
# Indexes
#
#  idx_meta_enchant_lookup                              (pvp_season_id,bracket,spec_id,slot)
#  idx_meta_enchant_unique                              (pvp_season_id,bracket,spec_id,slot,enchantment_id) UNIQUE
#  index_pvp_meta_enchant_popularity_on_enchantment_id  (enchantment_id)
#  index_pvp_meta_enchant_popularity_on_pvp_season_id   (pvp_season_id)
#
# Foreign Keys
#
#  fk_rails_...  (enchantment_id => enchantments.id)
#  fk_rails_...  (pvp_season_id => pvp_seasons.id)
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
