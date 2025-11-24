class CreateItems < ActiveRecord::Migration[8.1]
  def change
    create_table :items do |t|
      t.bigint :blizzard_id, null: false
      t.string :item_class
      t.string :item_subclass
      t.string :inventory_type
      t.integer :item_level
      t.integer :quality

      t.string :icon_url
      t.bigint :blizzard_media_id

      t.timestamps
    end

    add_index :items, :blizzard_id, unique: true
  end
end
