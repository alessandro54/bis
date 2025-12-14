class ChangePvpSeasonsBlizzardIdToInteger < ActiveRecord::Migration[8.1]
  def up
    change_column :pvp_seasons, :blizzard_id, "integer USING blizzard_id::integer"
    add_index :pvp_seasons, :blizzard_id, unique: true
  end

  def down
    remove_index :pvp_seasons, :blizzard_id
    change_column :pvp_seasons, :blizzard_id, :string
  end
end
