class AddStatsToCharacterItems < ActiveRecord::Migration[8.1]
  def change
    add_column :character_items, :stats, :jsonb, default: {}
  end
end
