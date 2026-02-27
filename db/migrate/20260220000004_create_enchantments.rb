class CreateEnchantments < ActiveRecord::Migration[8.1]
  def change
    create_table :enchantments do |t|
      t.bigint :blizzard_id, null: false
      t.timestamps
    end

    add_index :enchantments, :blizzard_id, unique: true
  end
end
