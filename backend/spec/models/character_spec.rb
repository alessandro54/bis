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
require 'rails_helper'

RSpec.describe Character, type: :model do
  describe "validations" do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:realm) }
    it { should validate_presence_of(:region) }
    it { should validate_uniqueness_of(:blizzard_id).scoped_to(:region) }
  end
end
