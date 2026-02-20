class CreatePvpLeaderboards < ActiveRecord::Migration[8.1]
  def change
    create_table :pvp_leaderboards do |t|
      t.string :bracket
      t.string :region
      t.datetime :last_synced_at

      t.references :pvp_season, null: false, foreign_key: true
      t.timestamps
    end

    add_index :pvp_leaderboards, %i[pvp_season_id bracket], unique: true
  end
end
