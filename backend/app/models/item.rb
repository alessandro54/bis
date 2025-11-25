# == Schema Information
#
# Table name: items
# Database name: primary
#
#  id                :bigint           not null, primary key
#  icon_url          :string
#  inventory_type    :string
#  item_class        :string
#  item_level        :integer
#  item_subclass     :string
#  quality           :integer
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  blizzard_id       :bigint           not null
#  blizzard_media_id :bigint
#
# Indexes
#
#  index_items_on_blizzard_id  (blizzard_id) UNIQUE
#
class Item < ApplicationRecord
  include Translatable

  has_many :item_translations, dependent: :destroy

  validates :blizzard_id, presence: true, uniqueness: true

  accepts_nested_attributes_for :translations
end
