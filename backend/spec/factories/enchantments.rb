# == Schema Information
#
# Table name: enchantments
# Database name: primary
#
#  id          :bigint           not null, primary key
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  blizzard_id :bigint           not null
#
# Indexes
#
#  index_enchantments_on_blizzard_id  (blizzard_id) UNIQUE
#
FactoryBot.define do
  factory :enchantment do
    blizzard_id { Faker::Number.number(digits: 7) }
  end
end
