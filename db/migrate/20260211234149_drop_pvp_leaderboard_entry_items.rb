class DropPvpLeaderboardEntryItems < ActiveRecord::Migration[8.1]
  def change
    drop_table :pvp_leaderboard_entry_items do |t|
      t.references :pvp_leaderboard_entry, null: false, foreign_key: true
      t.references :item, null: false, foreign_key: true
      t.string :slot
      t.integer :item_level
      t.string :context
      t.jsonb :raw
      t.timestamps
    end
  end
end
