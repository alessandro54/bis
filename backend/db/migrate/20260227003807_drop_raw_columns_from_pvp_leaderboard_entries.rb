class DropRawColumnsFromPvpLeaderboardEntries < ActiveRecord::Migration[8.1]
  def change
    remove_column :pvp_leaderboard_entries, :raw_equipment,      :binary
    remove_column :pvp_leaderboard_entries, :raw_specialization, :binary
  end
end
