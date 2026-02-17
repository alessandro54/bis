class AddEquipmentFingerprintToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :equipment_fingerprint, :string
    add_index  :characters, :equipment_fingerprint,
               name: "index_characters_on_equipment_fingerprint"
  end
end
