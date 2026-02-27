class ChangeColumnsToItem < ActiveRecord::Migration[8.1]
  def change
    remove_column :items, :item_level

    add_column :items, :meta_synced_at, :datetime
  end
end
