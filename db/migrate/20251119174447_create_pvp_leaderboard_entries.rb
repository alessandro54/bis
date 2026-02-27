class CreatePvpLeaderboardEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :pvp_leaderboard_entries do |t|
      t.integer :rank
      t.integer :rating
      t.integer :wins
      t.integer :losses
      t.string :spec
      t.integer :spec_id
      t.integer :class_id

      t.integer :item_level

      t.jsonb :gear_raw
      t.jsonb :talents_raw

      t.datetime :snapshot_at

      t.references :pvp_leaderboard, null: false, foreign_key: true
      t.references :character, null: false, foreign_key: true

      t.timestamps
    end

    add_index :pvp_leaderboard_entries, :rank
  end
end
