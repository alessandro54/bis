class UpsertLeaderboardEntries < ActiveRecord::Migration[8.1]
  def up
    # Keep only the most recent entry per character/leaderboard before adding unique constraint
    execute <<~SQL
      DELETE FROM pvp_leaderboard_entries
      WHERE id NOT IN (
        SELECT DISTINCT ON (character_id, pvp_leaderboard_id) id
        FROM pvp_leaderboard_entries
        ORDER BY character_id, pvp_leaderboard_id, snapshot_at DESC NULLS LAST, id DESC
      )
    SQL

    add_index :pvp_leaderboard_entries,
              %i[character_id pvp_leaderboard_id],
              unique: true,
              name: "idx_entries_unique_char_leaderboard"

    # No longer needed — snapshot_at is now just a "last seen" timestamp,
    # not used to discriminate between multiple entries per character.
    remove_index :pvp_leaderboard_entries, name: "index_entries_on_leaderboard_and_snapshot"
    remove_index :pvp_leaderboard_entries, name: "index_pvp_entries_on_character_and_snapshot"
    remove_index :pvp_leaderboard_entries, name: "index_pvp_entries_on_snapshot_at"
  end

  def down
    remove_index :pvp_leaderboard_entries, name: "idx_entries_unique_char_leaderboard"

    add_index :pvp_leaderboard_entries, %i[pvp_leaderboard_id snapshot_at],
              name: "index_entries_on_leaderboard_and_snapshot"
    add_index :pvp_leaderboard_entries, %i[character_id snapshot_at],
              name: "index_pvp_entries_on_character_and_snapshot"
    add_index :pvp_leaderboard_entries, :snapshot_at,
              name: "index_pvp_entries_on_snapshot_at"
  end
end
