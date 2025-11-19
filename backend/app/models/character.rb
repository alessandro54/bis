# == Schema Information
#
# Table name: characters
#
#  id          :bigint           not null, primary key
#  class_slug  :string
#  faction     :integer
#  name        :string
#  race        :string
#  realm       :string
#  region      :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  blizzard_id :string
#  class_id    :string
#
# Indexes
#
#  index_characters_on_blizzard_id_and_region     (blizzard_id,region) UNIQUE
#  index_characters_on_name_and_realm_and_region  (name,realm,region)
#
class Character < ApplicationRecord
  enum :faction, {
    alliance: 0,
    horde: 1
  }
end
