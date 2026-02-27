class CreatePvpMetaHeroTrees < ActiveRecord::Migration[8.0]
  def change
    create_table :pvp_meta_hero_trees do |t|
      t.references :pvp_season, null: false, foreign_key: true
      t.string     :bracket,              null: false
      t.integer    :spec_id,              null: false
      t.integer    :hero_talent_tree_id,  null: false
      t.string     :hero_talent_tree_name
      t.integer    :usage_count,          null: false, default: 0
      t.decimal    :usage_pct,            precision: 5, scale: 2
      t.decimal    :avg_rating,           precision: 7, scale: 2
      t.decimal    :avg_winrate,          precision: 5, scale: 4
      t.datetime   :snapshot_at,          null: false
      t.timestamps
    end
    add_index :pvp_meta_hero_trees,
      %i[pvp_season_id bracket spec_id],
      name: "idx_hero_trees_lookup"
  end
end
