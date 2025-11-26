# == Schema Information
#
# Table name: pvp_leaderboard_entry_items
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  context                  :string
#  item_level               :integer
#  raw                      :jsonb
#  slot                     :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  item_id                  :bigint           not null
#  pvp_leaderboard_entry_id :bigint           not null
#
# Indexes
#
#  index_entry_items_on_entry_and_slot                            (pvp_leaderboard_entry_id,slot) UNIQUE
#  index_pvp_leaderboard_entry_items_on_item_id                   (item_id)
#  index_pvp_leaderboard_entry_items_on_pvp_leaderboard_entry_id  (pvp_leaderboard_entry_id)
#
# Foreign Keys
#
#  fk_rails_...  (item_id => items.id)
#  fk_rails_...  (pvp_leaderboard_entry_id => pvp_leaderboard_entries.id)
#
FactoryBot.define do
  factory :pvp_leaderboard_entry_item do
    association :pvp_leaderboard_entry
    association :item
    slot { "MyString" }
    item_level { Faker::Number.between(from: 1, to: 1000) }
    context { Faker::Lorem.word }
    raw { {} }
  end
end
