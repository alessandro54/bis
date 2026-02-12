class CreatePvpMetaItemPopularity < ActiveRecord::Migration[8.0]
  def change
    create_table :pvp_meta_item_popularity do |t|
      t.references :pvp_season, null: false, foreign_key: true
      t.string     :bracket,        null: false
      t.integer    :spec_id,        null: false
      t.string     :slot,           null: false
      t.references :item,           null: false, foreign_key: true
      t.integer    :usage_count,    null: false, default: 0
      t.decimal    :usage_pct,      precision: 5, scale: 2
      t.decimal    :avg_item_level, precision: 6, scale: 2
      t.datetime   :snapshot_at,    null: false
      t.timestamps
    end
    add_index :pvp_meta_item_popularity,
      [:pvp_season_id, :bracket, :spec_id, :slot],
      name: "idx_item_popularity_lookup"
  end
end
