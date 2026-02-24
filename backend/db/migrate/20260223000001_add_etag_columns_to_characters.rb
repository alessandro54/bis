class AddEtagColumnsToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :equipment_etag, :string
    add_column :characters, :talents_etag,   :string
  end
end
