class CharacterItem < ApplicationRecord
  belongs_to :character
  belongs_to :item
  belongs_to :enchantment_source_item,
             class_name:  "Item",
             foreign_key: :enchantment_source_item_id,
             optional:    true

  validates :slot, uniqueness: { scope: :character_id }
end
