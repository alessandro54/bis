# == Schema Information
#
# Table name: items
# Database name: primary
#
#  id                :bigint           not null, primary key
#  icon_url          :string
#  inventory_type    :string
#  item_class        :string
#  item_subclass     :string
#  meta_synced_at    :datetime
#  quality           :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  blizzard_id       :bigint           not null
#  blizzard_media_id :bigint
#
# Indexes
#
#  index_items_on_blizzard_id  (blizzard_id) UNIQUE
#
FactoryBot.define do
  factory :item do
    blizzard_id    { Faker::Number.unique.number(digits: 8) }
    item_class     { "armor" }
    item_subclass  { "cloth" }
    inventory_type { "head" }
    quality        { "epic" }
  end
end
