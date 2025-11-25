class RemoveColumnsFromPvpLeaderboardEntry < ActiveRecord::Migration[8.1]
  def change
    remove_column :pvp_leaderboard_entries, :class_id
    remove_column :pvp_leaderboard_entries, :spec
  end
end
