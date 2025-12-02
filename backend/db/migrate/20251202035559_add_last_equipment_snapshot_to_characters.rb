class AddLastEquipmentSnapshotToCharacters < ActiveRecord::Migration[8.1]
  def change
    add_column :characters, :last_equipment_snapshot_at, :datetime

    change_column :characters, :class_id, :bigint, using: "class_id::bigint"
  end
end
