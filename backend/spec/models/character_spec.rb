# == Schema Information
#
# Table name: characters
# Database name: primary
#
#  id           :bigint           not null, primary key
#  avatar_url   :string
#  class_slug   :string
#  faction      :integer
#  inset_url    :string
#  is_private   :boolean          default(FALSE)
#  main_raw_url :string
#  name         :string
#  race         :string
#  realm        :string
#  region       :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  blizzard_id  :bigint
#  class_id     :string
#  race_id      :integer
#
# Indexes
#
#  index_characters_on_blizzard_id_and_region     (blizzard_id,region) UNIQUE
#  index_characters_on_name_and_realm_and_region  (name,realm,region)
#
require 'rails_helper'

RSpec.describe Character, type: :model do
  describe "validations" do
    subject { create(:character) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:realm) }
    it { is_expected.to validate_presence_of(:region) }

    it do
      is_expected.to validate_uniqueness_of(:name)
                       .scoped_to(%i[realm region])
    end

    it do
      is_expected.to validate_uniqueness_of(:blizzard_id)
                       .scoped_to(:region)
                       .case_insensitive
    end

    it do
      is_expected.to validate_numericality_of(:blizzard_id)
                       .only_integer
    end
  end
end
