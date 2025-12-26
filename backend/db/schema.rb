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

ActiveRecord::Schema[8.1].define(version: 2025_12_26_182800) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "characters", force: :cascade do |t|
    t.string "avatar_url"
    t.bigint "blizzard_id"
    t.bigint "class_id"
    t.string "class_slug"
    t.datetime "created_at", null: false
    t.integer "faction"
    t.string "inset_url"
    t.boolean "is_private", default: false
    t.datetime "last_equipment_snapshot_at"
    t.string "main_raw_url"
    t.datetime "meta_synced_at"
    t.string "name"
    t.string "race"
    t.integer "race_id"
    t.string "realm"
    t.string "region"
    t.datetime "updated_at", null: false
    t.index ["blizzard_id", "region"], name: "index_characters_on_blizzard_id_and_region", unique: true
    t.index ["is_private"], name: "index_characters_on_is_private", where: "(is_private = true)"
    t.index ["name", "realm", "region"], name: "index_characters_on_name_and_realm_and_region"
  end

  create_table "items", force: :cascade do |t|
    t.bigint "blizzard_id", null: false
    t.bigint "blizzard_media_id"
    t.datetime "created_at", null: false
    t.string "icon_url"
    t.string "inventory_type"
    t.string "item_class"
    t.string "item_subclass"
    t.datetime "meta_synced_at"
    t.integer "quality"
    t.datetime "updated_at", null: false
    t.index ["blizzard_id"], name: "index_items_on_blizzard_id", unique: true
  end

  create_table "job_performance_metrics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "duration", null: false
    t.string "error_class"
    t.string "job_class", null: false
    t.boolean "success", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_job_performance_metrics_on_created_at"
    t.index ["job_class", "created_at"], name: "index_job_performance_metrics_on_job_class_and_created_at"
    t.index ["job_class"], name: "index_job_performance_metrics_on_job_class"
    t.index ["success"], name: "index_job_performance_metrics_on_success"
  end

  create_table "pvp_leaderboard_entries", force: :cascade do |t|
    t.bigint "character_id", null: false
    t.datetime "created_at", null: false
    t.datetime "equipment_processed_at"
    t.integer "hero_talent_tree_id"
    t.string "hero_talent_tree_name"
    t.integer "item_level"
    t.integer "losses", default: 0
    t.bigint "pvp_leaderboard_id", null: false
    t.integer "rank"
    t.integer "rating"
    t.binary "raw_equipment"
    t.binary "raw_specialization"
    t.datetime "snapshot_at"
    t.integer "spec_id"
    t.datetime "specialization_processed_at"
    t.boolean "tier_4p_active", default: false
    t.integer "tier_set_id"
    t.string "tier_set_name"
    t.integer "tier_set_pieces"
    t.datetime "updated_at", null: false
    t.integer "wins", default: 0
    t.index ["character_id", "equipment_processed_at"], name: "index_pvp_entries_on_character_and_equipment_processed", where: "(equipment_processed_at IS NOT NULL)"
    t.index ["character_id", "snapshot_at"], name: "index_pvp_entries_on_character_and_snapshot"
    t.index ["character_id"], name: "index_pvp_leaderboard_entries_on_character_id"
    t.index ["hero_talent_tree_id"], name: "index_pvp_leaderboard_entries_on_hero_talent_tree_id"
    t.index ["id", "equipment_processed_at"], name: "index_entries_for_batch_processing"
    t.index ["pvp_leaderboard_id", "rating"], name: "index_entries_on_leaderboard_and_rating"
    t.index ["pvp_leaderboard_id", "spec_id", "rating"], name: "index_entries_for_spec_meta"
    t.index ["pvp_leaderboard_id"], name: "index_pvp_leaderboard_entries_on_pvp_leaderboard_id"
    t.index ["rank"], name: "index_pvp_leaderboard_entries_on_rank"
    t.index ["snapshot_at"], name: "index_pvp_entries_on_snapshot_at"
    t.index ["tier_set_id"], name: "index_pvp_leaderboard_entries_on_tier_set_id"
  end

  create_table "pvp_leaderboard_entry_items", force: :cascade do |t|
    t.string "context"
    t.datetime "created_at", null: false
    t.bigint "item_id", null: false
    t.integer "item_level"
    t.bigint "pvp_leaderboard_entry_id", null: false
    t.jsonb "raw"
    t.string "slot"
    t.datetime "updated_at", null: false
    t.index ["item_id"], name: "index_pvp_leaderboard_entry_items_on_item_id"
    t.index ["pvp_leaderboard_entry_id", "slot"], name: "index_entry_items_on_entry_and_slot", unique: true
    t.index ["pvp_leaderboard_entry_id"], name: "index_pvp_leaderboard_entry_items_on_pvp_leaderboard_entry_id"
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
    t.integer "blizzard_id"
    t.datetime "created_at", null: false
    t.string "display_name"
    t.datetime "end_time"
    t.boolean "is_current", default: false
    t.datetime "start_time"
    t.datetime "updated_at", null: false
    t.index ["blizzard_id"], name: "index_pvp_seasons_on_blizzard_id", unique: true
    t.index ["is_current"], name: "index_pvp_seasons_on_is_current"
    t.index ["updated_at"], name: "index_pvp_seasons_on_updated_at"
  end

  create_table "translations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.string "locale", null: false
    t.jsonb "meta", default: {}, null: false
    t.bigint "translatable_id", null: false
    t.string "translatable_type", null: false
    t.datetime "updated_at", null: false
    t.text "value", null: false
    t.index ["key"], name: "index_translations_on_key"
    t.index ["locale"], name: "index_translations_on_locale"
    t.index ["translatable_type", "translatable_id", "locale", "key"], name: "index_translations_on_translatable_and_locale_and_key", unique: true
    t.index ["translatable_type", "translatable_id"], name: "index_translations_on_translatable"
  end

  add_foreign_key "pvp_leaderboard_entries", "characters"
  add_foreign_key "pvp_leaderboard_entries", "pvp_leaderboards"
  add_foreign_key "pvp_leaderboard_entry_items", "items"
  add_foreign_key "pvp_leaderboard_entry_items", "pvp_leaderboard_entries"
  add_foreign_key "pvp_leaderboards", "pvp_seasons"
end
