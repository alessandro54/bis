class CreateCharacterTalents < ActiveRecord::Migration[8.0]
  def change
    create_table :character_talents do |t|
      t.references :character, null: false, foreign_key: true, index: false
      t.references :talent,    null: false, foreign_key: true
      t.string     :talent_type,  null: false
      t.integer    :rank,         default: 1
      t.integer    :slot_number
      t.timestamps
    end
    add_index :character_talents,
      [:character_id, :talent_id],
      unique: true, name: "idx_character_talents_on_char_and_talent"
    add_index :character_talents,
      [:character_id, :talent_type],
      name: "idx_character_talents_on_char_and_type"
  end
end
