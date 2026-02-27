class CreatePvpSyncCycles < ActiveRecord::Migration[8.0]
  def change
    create_table :pvp_sync_cycles do |t|
      t.references :pvp_season, null: false, foreign_key: true
      t.string     :status,                     null: false, default: "syncing_leaderboards"
      t.string     :regions,                    null: false, array: true, default: []
      t.datetime   :snapshot_at,                null: false
      t.integer    :expected_character_batches,  null: false, default: 0
      t.integer    :completed_character_batches, null: false, default: 0
      t.datetime   :completed_at
      t.timestamps
    end
    add_index :pvp_sync_cycles, %i[pvp_season_id status]
  end
end
