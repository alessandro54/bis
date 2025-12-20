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

  has_many :pvp_leaderboard_entry_items, dependent: :destroy
  has_many :pvp_leaderboard_entries, through: :pvp_leaderboard_entry_items

  validates :blizzard_id, presence: true, uniqueness: true

  accepts_nested_attributes_for :translations

  def meta_synced?
    meta_synced_at.present? && meta_synced_at > 1.week.ago
  end
end
