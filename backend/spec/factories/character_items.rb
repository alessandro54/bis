FactoryBot.define do
  factory :character_item do
    association :character
    association :item
    slot       { %w[HEAD CHEST HANDS LEGS FEET SHOULDER BACK WRIST WAIST FINGER1 TRINKET1 MAINHAND].sample }
    item_level { Faker::Number.between(from: 400, to: 700) }
    context    { Faker::Number.between(from: 1, to: 50) }
    bonus_list { [] }
    sockets    { [] }
  end
end
