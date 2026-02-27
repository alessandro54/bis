class DropNameFromTalents < ActiveRecord::Migration[8.1]
  def up
    remove_column :talents, :name
  end

  def down
    add_column :talents, :name, :string
  end
end
