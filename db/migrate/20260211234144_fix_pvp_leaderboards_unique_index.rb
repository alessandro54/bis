class FixPvpLeaderboardsUniqueIndex < ActiveRecord::Migration[8.0]
  def change
    remove_index :pvp_leaderboards,
      column: %i[pvp_season_id bracket],
      name:   "index_pvp_leaderboards_on_pvp_season_id_and_bracket"
    add_index :pvp_leaderboards,
      %i[pvp_season_id bracket region],
      unique: true, name: "idx_leaderboards_season_bracket_region"
  end
end
