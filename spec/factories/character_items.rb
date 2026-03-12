# == Schema Information
#
# Table name: character_items
# Database name: primary
#
#  id                         :bigint           not null, primary key
#  bonus_list                 :integer          default([]), is an Array
#  context                    :integer
#  crafting_stats             :string           default([]), is an Array
#  item_level                 :integer
#  slot                       :string           not null
#  sockets                    :jsonb
#  stats                      :jsonb
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  character_id               :bigint           not null
#  embellishment_spell_id     :integer
#  enchantment_id             :bigint
#  enchantment_source_item_id :bigint
#  item_id                    :bigint           not null
#  spec_id                    :integer          not null
#
# Indexes
#
#  idx_character_items_on_char_slot_spec    (character_id,slot,spec_id) UNIQUE
#  idx_character_items_on_char_spec         (character_id,spec_id)
#  index_character_items_on_enchantment_id  (enchantment_id) WHERE (enchantment_id IS NOT NULL)
#  index_character_items_on_item_id         (item_id)
#
# Foreign Keys
#
#  fk_rails_...  (character_id => characters.id)
#  fk_rails_...  (enchantment_id => enchantments.id)
#  fk_rails_...  (enchantment_source_item_id => items.id)
#  fk_rails_...  (item_id => items.id)
#
FactoryBot.define do
  factory :character_item do
    association :character
    association :item
    slot       { %w[HEAD CHEST HANDS LEGS FEET SHOULDER BACK WRIST WAIST FINGER1 TRINKET1 MAINHAND].sample }
    item_level { Faker::Number.between(from: 400, to: 700) }
    context    { Faker::Number.between(from: 1, to: 50) }
    bonus_list { [] }
    sockets    { [] }
    spec_id    { 262 }
  end
end
