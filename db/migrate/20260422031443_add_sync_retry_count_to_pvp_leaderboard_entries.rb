class AddSyncRetryCountToPvpLeaderboardEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :pvp_leaderboard_entries, :sync_retry_count, :integer, default: 0, null: false
  end
end
