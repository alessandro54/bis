class CreatePvpMetaTalentPopularity < ActiveRecord::Migration[8.1]
  def change
    create_table :pvp_meta_talent_popularity do |t|
      t.bigint   :pvp_season_id, null: false
      t.string   :bracket,       null: false
      t.integer  :spec_id,       null: false
      t.bigint   :talent_id,     null: false
      t.string   :talent_type,   null: false
      t.integer  :usage_count,   null: false, default: 0
      t.decimal  :usage_pct,     precision: 5, scale: 2
      t.datetime :snapshot_at,   null: false
      t.timestamps
    end

    add_index :pvp_meta_talent_popularity, :pvp_season_id
    add_index :pvp_meta_talent_popularity, :talent_id
    add_index :pvp_meta_talent_popularity,
              %i[pvp_season_id bracket spec_id talent_id],
              unique: true, name: "idx_meta_talent_unique"
    add_index :pvp_meta_talent_popularity,
              %i[pvp_season_id bracket spec_id talent_type],
              name: "idx_meta_talent_lookup"

    add_foreign_key :pvp_meta_talent_popularity, :pvp_seasons
    add_foreign_key :pvp_meta_talent_popularity, :talents
  end
end
