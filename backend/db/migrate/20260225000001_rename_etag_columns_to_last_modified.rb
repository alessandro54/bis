class RenameEtagColumnsToLastModified < ActiveRecord::Migration[8.1]
  def change
    rename_column :characters, :equipment_etag, :equipment_last_modified
    rename_column :characters, :talents_etag,   :talents_last_modified
  end
end