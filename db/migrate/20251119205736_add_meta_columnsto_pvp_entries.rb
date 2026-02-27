class AddMetaColumnstoPvpEntries < ActiveRecord::Migration[8.1]
  def change
    change_table :pvp_leaderboard_entries, bulk: true do |t|
      t.integer :hero_talent_tree_id
      t.string  :hero_talent_tree_name

      t.integer :tier_set_id
      t.string  :tier_set_name
      t.integer :tier_set_pieces
      t.boolean :tier_4p_active, default: false
    end

    add_index :pvp_leaderboard_entries, :hero_talent_tree_id
    add_index :pvp_leaderboard_entries, :tier_set_id
  end
end
