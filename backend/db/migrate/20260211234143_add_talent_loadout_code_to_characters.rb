class AddTalentLoadoutCodeToCharacters < ActiveRecord::Migration[8.0]
  def change
    add_column :characters, :talent_loadout_code, :string
    add_index  :characters, :talent_loadout_code
  end
end
