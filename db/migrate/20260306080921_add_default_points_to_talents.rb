class AddDefaultPointsToTalents < ActiveRecord::Migration[8.1]
  def change
    add_column :talents, :default_points, :integer, default: 0, null: false
  end
end
