class RemoveColumnsFromPvpLeaderboardEntry < ActiveRecord::Migration[8.1]
  def up
    remove_column :pvp_leaderboard_entries, :class_id
    remove_column :pvp_leaderboard_entries, :spec

    change_column_default :pvp_leaderboard_entries, :wins, 0
    change_column_default :pvp_leaderboard_entries, :losses, 0
  end

  def down
    add_column :pvp_leaderboard_entries, :class_id, :integer
    add_column :pvp_leaderboard_entries, :spec, :string
  end
end
