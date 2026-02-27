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
class Talent < ApplicationRecord
  include Translatable

  has_many :character_talents, dependent: :restrict_with_exception

  validates :blizzard_id, presence: true, uniqueness: true
  validates :talent_type, presence: true, inclusion: { in: %w[class spec hero pvp] }
end
