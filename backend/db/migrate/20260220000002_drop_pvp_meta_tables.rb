class DropPvpMetaTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :pvp_meta_talent_picks
    drop_table :pvp_meta_talent_builds
    drop_table :pvp_meta_item_popularity
    drop_table :pvp_meta_hero_trees
    remove_column :pvp_sync_cycles, :expected_aggregation_brackets
    remove_column :pvp_sync_cycles, :completed_aggregation_brackets
  end

  def down
    add_column :pvp_sync_cycles, :expected_aggregation_brackets,  :integer, default: 0, null: false
    add_column :pvp_sync_cycles, :completed_aggregation_brackets, :integer, default: 0, null: false

    create_table :pvp_meta_hero_trees do |t|
      t.decimal  "avg_rating",            precision: 7, scale: 2
      t.decimal  "avg_winrate",           precision: 5, scale: 4
      t.string   "bracket",               null: false
      t.integer  "hero_talent_tree_id",   null: false
      t.string   "hero_talent_tree_name"
      t.bigint   "pvp_season_id",         null: false
      t.datetime "snapshot_at",           null: false
      t.integer  "spec_id",               null: false
      t.integer  "usage_count",           default: 0, null: false
      t.decimal  "usage_pct",             precision: 5, scale: 2
      t.timestamps
      t.index ["pvp_season_id", "bracket", "spec_id"], name: "idx_hero_trees_lookup"
      t.index ["pvp_season_id"]
    end
    add_foreign_key :pvp_meta_hero_trees, :pvp_seasons

    create_table :pvp_meta_item_popularity do |t|
      t.decimal  "avg_item_level",  precision: 6, scale: 2
      t.string   "bracket",         null: false
      t.bigint   "item_id",         null: false
      t.bigint   "pvp_season_id",   null: false
      t.string   "slot",            null: false
      t.datetime "snapshot_at",     null: false
      t.integer  "spec_id",         null: false
      t.integer  "usage_count",     default: 0, null: false
      t.decimal  "usage_pct",       precision: 5, scale: 2
      t.timestamps
      t.index ["item_id"]
      t.index ["pvp_season_id", "bracket", "spec_id", "slot"], name: "idx_item_popularity_lookup"
      t.index ["pvp_season_id"]
    end
    add_foreign_key :pvp_meta_item_popularity, :items
    add_foreign_key :pvp_meta_item_popularity, :pvp_seasons

    create_table :pvp_meta_talent_builds do |t|
      t.decimal  "avg_rating",           precision: 7, scale: 2
      t.decimal  "avg_winrate",          precision: 5, scale: 4
      t.string   "bracket",              null: false
      t.bigint   "pvp_season_id",        null: false
      t.datetime "snapshot_at",          null: false
      t.integer  "spec_id",              null: false
      t.string   "talent_loadout_code",  null: false
      t.integer  "total_entries",        default: 0, null: false
      t.integer  "usage_count",          default: 0, null: false
      t.decimal  "usage_pct",            precision: 5, scale: 2
      t.timestamps
      t.index ["pvp_season_id", "bracket", "spec_id"], name: "idx_talent_builds_lookup"
      t.index ["pvp_season_id"]
    end
    add_foreign_key :pvp_meta_talent_builds, :pvp_seasons

    create_table :pvp_meta_talent_picks do |t|
      t.decimal  "avg_rating",     precision: 7, scale: 2
      t.string   "bracket",        null: false
      t.decimal  "pick_rate",      precision: 5, scale: 4
      t.bigint   "pvp_season_id",  null: false
      t.datetime "snapshot_at",    null: false
      t.integer  "spec_id",        null: false
      t.bigint   "talent_id",      null: false
      t.string   "talent_type",    null: false
      t.integer  "usage_count",    default: 0, null: false
      t.timestamps
      t.index ["pvp_season_id", "bracket", "spec_id", "talent_type"], name: "idx_talent_picks_lookup"
      t.index ["pvp_season_id"]
      t.index ["talent_id"]
    end
    add_foreign_key :pvp_meta_talent_picks, :pvp_seasons
    add_foreign_key :pvp_meta_talent_picks, :talents
  end
end
