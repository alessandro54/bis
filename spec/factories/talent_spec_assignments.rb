# == Schema Information
#
# Table name: talent_spec_assignments
# Database name: primary
#
#  id             :bigint           not null, primary key
#  default_points :integer          default(0), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  spec_id        :integer          not null
#  talent_id      :bigint           not null
#
# Indexes
#
#  index_talent_spec_assignments_on_spec_id                (spec_id)
#  index_talent_spec_assignments_on_talent_id_and_spec_id  (talent_id,spec_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (talent_id => talents.id)
#
FactoryBot.define do
  factory :talent_spec_assignment do
    talent
    spec_id        { 71 }
    default_points { 0 }
  end
end
