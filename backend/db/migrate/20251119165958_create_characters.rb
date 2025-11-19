class CreateCharacters < ActiveRecord::Migration[8.1]
  def change
    create_table :characters do |t|
      t.string :blizzard_id
      t.string :name
      t.string :realm
      t.string :region
      t.string :class_id
      t.string :class_slug
      t.string :race
      t.integer :faction

      t.timestamps
    end

    add_index :characters, [ :blizzard_id, :region ], unique: true

    add_index :characters,  [ :name, :realm, :region ]
  end
end
