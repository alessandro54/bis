# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_11_24_204215) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "characters", force: :cascade do |t|
    t.bigint "blizzard_id"
    t.string "class_id"
    t.string "class_slug"
    t.datetime "created_at", null: false
    t.integer "faction"
    t.string "name"
    t.string "race"
    t.string "realm"
    t.string "region"
    t.datetime "updated_at", null: false
    t.index ["blizzard_id", "region"], name: "index_characters_on_blizzard_id_and_region", unique: true
    t.index ["name", "realm", "region"], name: "index_characters_on_name_and_realm_and_region"
  end

  create_table "item_translations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.bigint "item_id", null: false
    t.string "locale"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["item_id", "locale"], name: "index_item_translations_on_item_id_and_locale", unique: true
    t.index ["item_id"], name: "index_item_translations_on_item_id"
  end

  create_table "items", force: :cascade do |t|
    t.bigint "blizzard_id", null: false
    t.bigint "blizzard_media_id"
    t.datetime "created_at", null: false
    t.string "icon_url"
    t.string "inventory_type"
    t.string "item_class"
    t.integer "item_level"
    t.string "item_subclass"
    t.integer "quality"
    t.datetime "updated_at", null: false
    t.index ["blizzard_id"], name: "index_items_on_blizzard_id", unique: true
  end

  create_table "pvp_leaderboard_entries", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.integer "class_id"
    t.datetime "created_at", null: false
    t.jsonb "gear_raw"
    t.integer "hero_talent_tree_id"
    t.string "hero_talent_tree_name"
    t.integer "item_level"
    t.integer "losses"
    t.bigint "pvp_leaderboard_id", null: false
    t.integer "rank"
    t.integer "rating"
    t.datetime "snapshot_at"
    t.string "spec"
    t.integer "spec_id"
    t.jsonb "talents_raw"
    t.boolean "tier_4p_active", default: false
    t.integer "tier_set_id"
    t.string "tier_set_name"
    t.integer "tier_set_pieces"
    t.datetime "updated_at", null: false
    t.integer "wins"
    t.index ["character_id"], name: "index_pvp_leaderboard_entries_on_character_id"
    t.index ["hero_talent_tree_id"], name: "index_pvp_leaderboard_entries_on_hero_talent_tree_id"
    t.index ["pvp_leaderboard_id"], name: "index_pvp_leaderboard_entries_on_pvp_leaderboard_id"
    t.index ["rank"], name: "index_pvp_leaderboard_entries_on_rank"
    t.index ["tier_set_id"], name: "index_pvp_leaderboard_entries_on_tier_set_id"
  end

  create_table "pvp_leaderboards", force: :cascade do |t|
    t.string "bracket"
    t.datetime "created_at", null: false
    t.datetime "last_synced_at"
    t.bigint "pvp_season_id", null: false
    t.string "region"
    t.datetime "updated_at", null: false
    t.index ["pvp_season_id", "bracket"], name: "index_pvp_leaderboards_on_pvp_season_id_and_bracket", unique: true
    t.index ["pvp_season_id"], name: "index_pvp_leaderboards_on_pvp_season_id"
  end

  create_table "pvp_seasons", force: :cascade do |t|
    t.string "blizzard_id"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.datetime "end_time"
    t.boolean "is_current", default: false
    t.datetime "start_time"
    t.datetime "updated_at", null: false
    t.index ["is_current"], name: "index_pvp_seasons_on_is_current"
    t.index ["updated_at"], name: "index_pvp_seasons_on_updated_at"
  end

  add_foreign_key "item_translations", "items"
  add_foreign_key "pvp_leaderboard_entries", "characters"
  add_foreign_key "pvp_leaderboard_entries", "pvp_leaderboards"
  add_foreign_key "pvp_leaderboards", "pvp_seasons"
end
