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
# Indexes
#
#  idx_character_talents_on_char_and_talent  (character_id,talent_id) UNIQUE
#  idx_character_talents_on_char_and_type    (character_id,talent_type)
#  index_character_talents_on_talent_id      (talent_id)
#
# Foreign Keys
#
#  fk_rails_...  (character_id => characters.id)
#  fk_rails_...  (talent_id => talents.id)
#
class CharacterTalent < ApplicationRecord
  belongs_to :character
  belongs_to :talent
end
