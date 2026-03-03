class AddSpecIdToCharacterItemsAndTalents < ActiveRecord::Migration[8.1]
  def up
    # --- Phase 1a: Add spec_id columns ---
    add_column :character_items, :spec_id, :integer
    add_column :character_talents, :spec_id, :integer

    # --- Phase 1b: Backfill from character's latest entry spec_id ---
    execute <<~SQL
      UPDATE character_items ci
      SET spec_id = sub.spec_id
      FROM (
        SELECT DISTINCT ON (e.character_id) e.character_id, e.spec_id
        FROM pvp_leaderboard_entries e
        WHERE e.spec_id IS NOT NULL
        ORDER BY e.character_id, e.updated_at DESC
      ) sub
      WHERE ci.character_id = sub.character_id
        AND ci.spec_id IS NULL
    SQL

    execute <<~SQL
      UPDATE character_talents ct
      SET spec_id = sub.spec_id
      FROM (
        SELECT DISTINCT ON (e.character_id) e.character_id, e.spec_id
        FROM pvp_leaderboard_entries e
        WHERE e.spec_id IS NOT NULL
        ORDER BY e.character_id, e.updated_at DESC
      ) sub
      WHERE ct.character_id = sub.character_id
        AND ct.spec_id IS NULL
    SQL

    # Remove orphan rows where backfill couldn't find a spec_id
    execute "DELETE FROM character_items WHERE spec_id IS NULL"
    execute "DELETE FROM character_talents WHERE spec_id IS NULL"

    # --- Phase 1c: Make spec_id NOT NULL, update unique constraints ---
    change_column_null :character_items, :spec_id, false
    change_column_null :character_talents, :spec_id, false

    remove_index :character_items, name: "idx_character_items_on_char_and_slot"
    add_index :character_items, [:character_id, :slot, :spec_id],
              unique: true, name: "idx_character_items_on_char_slot_spec"

    remove_index :character_talents, name: "idx_character_talents_on_char_and_talent"
    add_index :character_talents, [:character_id, :talent_id, :spec_id],
              unique: true, name: "idx_character_talents_on_char_talent_spec"

    # --- Phase 1d: Replace fingerprint columns with per-spec JSONB ---
    # Backfill old fingerprints into new JSONB columns before removing
    add_column :characters, :spec_equipment_fingerprints, :jsonb, default: {}
    add_column :characters, :spec_talent_loadout_codes, :jsonb, default: {}

    execute <<~SQL
      UPDATE characters c
      SET spec_equipment_fingerprints = jsonb_build_object(sub.spec_id::text, c.equipment_fingerprint)
      FROM (
        SELECT DISTINCT ON (e.character_id) e.character_id, e.spec_id
        FROM pvp_leaderboard_entries e
        WHERE e.spec_id IS NOT NULL
        ORDER BY e.character_id, e.updated_at DESC
      ) sub
      WHERE c.id = sub.character_id
        AND c.equipment_fingerprint IS NOT NULL
    SQL

    execute <<~SQL
      UPDATE characters c
      SET spec_talent_loadout_codes = jsonb_build_object(sub.spec_id::text, c.talent_loadout_code)
      FROM (
        SELECT DISTINCT ON (e.character_id) e.character_id, e.spec_id
        FROM pvp_leaderboard_entries e
        WHERE e.spec_id IS NOT NULL
        ORDER BY e.character_id, e.updated_at DESC
      ) sub
      WHERE c.id = sub.character_id
        AND c.talent_loadout_code IS NOT NULL
    SQL

    remove_index :characters, name: "index_characters_on_equipment_fingerprint"
    remove_index :characters, name: "index_characters_on_talent_loadout_code"
    remove_column :characters, :equipment_fingerprint
    remove_column :characters, :talent_loadout_code
  end

  def down
    # Re-add old columns
    add_column :characters, :equipment_fingerprint, :string
    add_column :characters, :talent_loadout_code, :string
    add_index :characters, :equipment_fingerprint, name: "index_characters_on_equipment_fingerprint"
    add_index :characters, :talent_loadout_code, name: "index_characters_on_talent_loadout_code"

    # Restore fingerprints from JSONB (best effort: pick first value)
    execute <<~SQL
      UPDATE characters
      SET equipment_fingerprint = (
        SELECT value FROM jsonb_each_text(spec_equipment_fingerprints) LIMIT 1
      )
      WHERE spec_equipment_fingerprints != '{}'::jsonb
    SQL

    execute <<~SQL
      UPDATE characters
      SET talent_loadout_code = (
        SELECT value FROM jsonb_each_text(spec_talent_loadout_codes) LIMIT 1
      )
      WHERE spec_talent_loadout_codes != '{}'::jsonb
    SQL

    remove_column :characters, :spec_equipment_fingerprints
    remove_column :characters, :spec_talent_loadout_codes

    # Restore old indexes
    remove_index :character_items, name: "idx_character_items_on_char_slot_spec"
    add_index :character_items, [:character_id, :slot],
              unique: true, name: "idx_character_items_on_char_and_slot"

    remove_index :character_talents, name: "idx_character_talents_on_char_talent_spec"
    add_index :character_talents, [:character_id, :talent_id],
              unique: true, name: "idx_character_talents_on_char_and_talent"

    # Remove spec_id columns
    remove_column :character_items, :spec_id
    remove_column :character_talents, :spec_id
  end
end
