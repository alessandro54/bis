class CreateTalentSpecAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :talent_spec_assignments do |t|
      t.bigint  :talent_id, null: false
      t.integer :spec_id,   null: false
      t.timestamps
    end

    add_index :talent_spec_assignments, %i[talent_id spec_id], unique: true
    add_index :talent_spec_assignments, :spec_id
    add_foreign_key :talent_spec_assignments, :talents
  end
end
