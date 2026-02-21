class ChangeItemQualityToString < ActiveRecord::Migration[8.1]
  def up
    change_column :items, :quality, :string
  end

  def down
    change_column :items, :quality, :integer, using: "quality::integer"
  end
end
