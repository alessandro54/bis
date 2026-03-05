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
class Enchantment < ApplicationRecord
  include Translatable

  has_many :character_items, dependent: :nullify

  validates :blizzard_id, presence: true, uniqueness: true
end
