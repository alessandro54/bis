# == Schema Information
#
# Table name: talents
# Database name: primary
#
#  id          :bigint           not null, primary key
#  talent_type :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  blizzard_id :bigint           not null
#  spell_id    :integer
#
# Indexes
#
#  index_talents_on_blizzard_id                  (blizzard_id) UNIQUE
#  index_talents_on_talent_type_and_blizzard_id  (talent_type,blizzard_id)
#
FactoryBot.define do
  factory :talent do
    blizzard_id { Faker::Number.unique.number(digits: 6) }
    talent_type { %w[class spec hero pvp].sample }
  end
end
