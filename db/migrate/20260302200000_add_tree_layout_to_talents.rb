class AddTreeLayoutToTalents < ActiveRecord::Migration[8.1]
  def change
    add_column :talents, :node_id,     :bigint
    add_column :talents, :display_row, :integer
    add_column :talents, :display_col, :integer
    add_column :talents, :max_rank,    :integer, default: 1, null: false
    add_column :talents, :icon_url,    :string

    add_index :talents, :node_id
  end
end
