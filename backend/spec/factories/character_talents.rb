# == Schema Information
#
# Table name: character_talents
# Database name: primary
#
#  id           :bigint           not null, primary key
#  rank         :integer          default(1)
#  slot_number  :integer
#  talent_type  :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  character_id :bigint           not null
#  talent_id    :bigint           not null
#
FactoryBot.define do
  factory :character_talent do
    association :character
    association :talent
    talent_type { talent.talent_type }
    rank        { 1 }
    slot_number { nil }
  end
end
