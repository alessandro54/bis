class AddColumnsToCharacter < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :inset_url, :string
    add_column :characters, :avatar_url, :string
    add_column :characters, :main_raw_url, :string
    add_column :characters, :race_id, :integer

    add_column :characters, :is_private, :boolean, default: false
  end
end
