# == Schema Information
#
# Table name: talent_prerequisites
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  node_id              :bigint           not null
#  prerequisite_node_id :bigint           not null
#
# Indexes
#
#  idx_talent_prerequisites_unique        (node_id,prerequisite_node_id) UNIQUE
#  index_talent_prerequisites_on_node_id  (node_id)
#
class TalentPrerequisite < ApplicationRecord
  validates :node_id,              presence: true
  validates :prerequisite_node_id, presence: true
end
