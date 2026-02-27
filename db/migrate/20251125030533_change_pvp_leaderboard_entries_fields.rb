class ChangePvpLeaderboardEntriesFields < ActiveRecord::Migration[8.1]
  def change
    rename_column :pvp_leaderboard_entries, :gear_raw, :raw_equipment
    rename_column :pvp_leaderboard_entries, :talents_raw, :raw_specialization
  end
end
