class CreateTalents < ActiveRecord::Migration[8.0]
  def change
    create_table :talents do |t|
      t.bigint  :blizzard_id, null: false
      t.string  :name
      t.string  :talent_type, null: false
      t.integer :spell_id
      t.timestamps
    end
    add_index :talents, :blizzard_id, unique: true
    add_index :talents, %i[talent_type blizzard_id]
  end
end
