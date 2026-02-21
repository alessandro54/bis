class ChangeCharacterItemsEnchantmentIdToFk < ActiveRecord::Migration[8.1]
  def up
    remove_index  :character_items, name: "index_character_items_on_enchantment_id"
    change_column :character_items, :enchantment_id, :bigint

    # Backfill enchantment stubs for any existing rows that stored raw Blizzard
    # enchantment IDs before the FK existed. Full metadata can be synced later.
    blizzard_ids = execute(
      "SELECT DISTINCT enchantment_id FROM character_items WHERE enchantment_id IS NOT NULL"
    ).column_values(0).map(&:to_i)

    if blizzard_ids.any?
      now    = Time.current.iso8601
      values = blizzard_ids.map { |id| "#{id}, '#{now}', '#{now}'" }.join("), (")
      execute <<~SQL
        INSERT INTO enchantments (blizzard_id, created_at, updated_at)
        VALUES (#{values})
        ON CONFLICT (blizzard_id) DO NOTHING
      SQL

      # Repoint enchantment_id from Blizzard ID → our DB id
      execute <<~SQL
        UPDATE character_items ci
        SET enchantment_id = e.id
        FROM enchantments e
        WHERE e.blizzard_id = ci.enchantment_id
          AND ci.enchantment_id IS NOT NULL
      SQL
    end

    add_foreign_key :character_items, :enchantments, column: :enchantment_id
    add_index :character_items, :enchantment_id,
              name:  "index_character_items_on_enchantment_id",
              where: "enchantment_id IS NOT NULL"
  end

  def down
    remove_foreign_key :character_items, column: :enchantment_id
    remove_index  :character_items, name: "index_character_items_on_enchantment_id"
    change_column :character_items, :enchantment_id, :integer
    add_index :character_items, :enchantment_id,
              name:  "index_character_items_on_enchantment_id",
              where: "enchantment_id IS NOT NULL"
  end
end
