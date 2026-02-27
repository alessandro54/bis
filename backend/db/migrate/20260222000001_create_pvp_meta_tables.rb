class CreatePvpMetaTables < ActiveRecord::Migration[8.1]
  def change
    create_table :pvp_meta_item_popularity do |t|
      t.references :pvp_season,   null: false, foreign_key: true
      t.string     :bracket,      null: false
      t.integer    :spec_id,      null: false
      t.string     :slot,         null: false
      t.references :item,         null: false, foreign_key: true
      t.integer    :usage_count,  null: false, default: 0
      t.decimal    :usage_pct,    precision: 5, scale: 2
      t.datetime   :snapshot_at,  null: false
      t.timestamps
    end

    add_index :pvp_meta_item_popularity,
              %i[pvp_season_id bracket spec_id slot],
              name: "idx_meta_item_lookup"
    add_index :pvp_meta_item_popularity,
              %i[pvp_season_id bracket spec_id slot item_id],
              unique: true,
              name:   "idx_meta_item_unique"

    create_table :pvp_meta_enchant_popularity do |t|
      t.references :pvp_season,     null: false, foreign_key: true
      t.string     :bracket,        null: false
      t.integer    :spec_id,        null: false
      t.string     :slot,           null: false
      t.references :enchantment,    null: false, foreign_key: true
      t.integer    :usage_count,    null: false, default: 0
      t.decimal    :usage_pct,      precision: 5, scale: 2
      t.datetime   :snapshot_at,    null: false
      t.timestamps
    end

    add_index :pvp_meta_enchant_popularity,
              %i[pvp_season_id bracket spec_id slot],
              name: "idx_meta_enchant_lookup"
    add_index :pvp_meta_enchant_popularity,
              %i[pvp_season_id bracket spec_id slot enchantment_id],
              unique: true,
              name:   "idx_meta_enchant_unique"

    create_table :pvp_meta_gem_popularity do |t|
      t.references :pvp_season,   null: false, foreign_key: true
      t.string     :bracket,      null: false
      t.integer    :spec_id,      null: false
      t.string     :slot,         null: false
      t.string     :socket_type,  null: false
      t.references :item,         null: false, foreign_key: true
      t.integer    :usage_count,  null: false, default: 0
      t.decimal    :usage_pct,    precision: 5, scale: 2
      t.datetime   :snapshot_at,  null: false
      t.timestamps
    end

    add_index :pvp_meta_gem_popularity,
              %i[pvp_season_id bracket spec_id slot],
              name: "idx_meta_gem_lookup"
    add_index :pvp_meta_gem_popularity,
              %i[pvp_season_id bracket spec_id slot socket_type item_id],
              unique: true,
              name:   "idx_meta_gem_unique"
  end
end
