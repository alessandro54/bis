class AddColumnsToLeaderboardEntry < ActiveRecord::Migration[8.1]
  def change
    add_column :pvp_leaderboard_entries, :equipment_processed_at, :datetime
    add_column :pvp_leaderboard_entries, :specialization_processed_at, :datetime
  end
end
