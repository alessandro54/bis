class AddAggregationIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Used in item/enchant/gem aggregation CTEs: JOIN character_items ON character_id AND spec_id
    add_index :character_items, [:character_id, :spec_id],
              name: "idx_character_items_on_char_spec",
              algorithm: :concurrently

    # Used in talent aggregation CTE: JOIN character_talents ON character_id AND spec_id
    add_index :character_talents, [:character_id, :spec_id],
              name: "idx_character_talents_on_char_spec",
              algorithm: :concurrently
  end
end
