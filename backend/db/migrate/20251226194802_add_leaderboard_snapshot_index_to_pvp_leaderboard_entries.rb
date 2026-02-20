class AddLeaderboardSnapshotIndexToPvpLeaderboardEntries < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Compound index for faster latest_snapshot_for_bracket queries
    # This allows the DB to efficiently filter by leaderboard_id AND snapshot_at together
    add_index :pvp_leaderboard_entries,
              %i[pvp_leaderboard_id snapshot_at],
              name:          "index_entries_on_leaderboard_and_snapshot",
              algorithm:     :concurrently,
              if_not_exists: true
  end
end
