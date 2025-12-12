class AddPerformanceIndexesToTables < ActiveRecord::Migration[8.1]
  def change
    # Add composite index for character_id + snapshot_at for faster lookups in LastEquipmentSnapshotFinderService
    add_index :pvp_leaderboard_entries, [:character_id, :snapshot_at],
              name: "index_pvp_entries_on_character_and_snapshot"

    # Add composite index for equipment_processed_at queries in snapshot finder
    add_index :pvp_leaderboard_entries, [:character_id, :equipment_processed_at],
              name: "index_pvp_entries_on_character_and_equipment_processed",
              where: "equipment_processed_at IS NOT NULL AND specialization_processed_at IS NOT NULL"

    # Add index on is_private to quickly filter out private characters
    add_index :characters, :is_private,
              name: "index_characters_on_is_private",
              where: "is_private = true"

    # Add index on snapshot_at for time-based queries
    add_index :pvp_leaderboard_entries, :snapshot_at,
              name: "index_pvp_entries_on_snapshot_at"
  end
end
