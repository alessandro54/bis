class AddPerformanceIndexesToPvpLeaderboardEntries < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Index for rating-based leaderboard queries (sorting by rating within a bracket)
    add_index :pvp_leaderboard_entries,
              [:pvp_leaderboard_id, :rating],
              name: "index_entries_on_leaderboard_and_rating",
              algorithm: :concurrently,
              if_not_exists: true

    # Index for spec-based meta queries (filtering by spec within a bracket, sorted by rating)
    add_index :pvp_leaderboard_entries,
              [:pvp_leaderboard_id, :spec_id, :rating],
              name: "index_entries_for_spec_meta",
              algorithm: :concurrently,
              if_not_exists: true

    # Composite index for efficient batch processing query
    # Filters by equipment_processed_at TTL check
    add_index :pvp_leaderboard_entries,
              [:id, :equipment_processed_at],
              name: "index_entries_for_batch_processing",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
