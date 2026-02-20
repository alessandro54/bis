class CreateCharacterItems < ActiveRecord::Migration[8.1]
  def change
    create_table :character_items do |t|
      t.references :character,  null: false, foreign_key: true, index: false
      t.references :item,       null: false, foreign_key: true
      t.string  :slot, null: false
      t.integer :item_level
      t.integer :context
      t.integer :enchantment_id
      t.bigint  :enchantment_source_item_id
      t.integer :embellishment_spell_id
      t.integer :bonus_list, array: true, default: []
      t.jsonb   :sockets,                 default: []
      t.timestamps
    end

    add_index :character_items, %i[character_id slot],
              unique: true,
              name:   "idx_character_items_on_char_and_slot"

    add_index :character_items, :enchantment_id,
              where: "enchantment_id IS NOT NULL",
              name:  "index_character_items_on_enchantment_id"

    add_foreign_key :character_items, :items, column: :enchantment_source_item_id
  end
end
