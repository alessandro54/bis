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

ActiveRecord::Schema[8.1].define(version: 0) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "alembic_version", primary_key: "version_num", id: { type: :string, limit: 32 }, force: :cascade do |t|
  end

  create_table "characters", id: :serial, force: :cascade do |t|
    t.integer "blizzard_id", null: false
    t.integer "class_id"
    t.datetime "created_at", precision: nil, null: false
    t.string "faction"
    t.string "name", null: false
    t.string "realm_slug", null: false
    t.string "region", null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["blizzard_id"], name: "ix_characters_blizzard_id"
    t.index ["class_id"], name: "ix_characters_class_id"
    t.index ["faction"], name: "ix_characters_faction"
    t.index ["id"], name: "ix_characters_id"
    t.index ["name"], name: "ix_characters_name"
    t.index ["realm_slug"], name: "ix_characters_realm_slug"
    t.index ["region"], name: "ix_characters_region"
    t.unique_constraint ["blizzard_id"], name: "uq_character_blizzard_id"
    t.unique_constraint ["region", "realm_slug", "name"], name: "uq_character_identity"
  end

  create_table "pvp_seasons", id: :serial, force: :cascade do |t|
    t.boolean "is_current", null: false
    t.json "name_json"
    t.json "raw_json"
    t.datetime "updated_at", precision: nil, null: false
    t.index ["id"], name: "ix_pvp_seasons_id"
    t.index ["is_current"], name: "ix_pvp_seasons_is_current"
    t.index ["updated_at"], name: "ix_pvp_seasons_updated_at"
  end
end
