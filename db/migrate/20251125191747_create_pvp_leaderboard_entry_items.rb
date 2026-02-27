class CreatePvpLeaderboardEntryItems < ActiveRecord::Migration[8.1]
  def change
    create_table :pvp_leaderboard_entry_items do |t|
      t.references :pvp_leaderboard_entry, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: true
      t.string :slot
      t.integer :item_level
      t.string :context
      t.jsonb :raw

      t.timestamps
    end

    add_index :pvp_leaderboard_entry_items,
              %i[pvp_leaderboard_entry_id slot],
              unique: true,
              name:   "index_entry_items_on_entry_and_slot"
  end
end
