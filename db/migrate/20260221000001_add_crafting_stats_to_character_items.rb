class AddCraftingStatsToCharacterItems < ActiveRecord::Migration[8.1]
  def change
    add_column :character_items, :crafting_stats, :string, array: true, default: []
  end
end
