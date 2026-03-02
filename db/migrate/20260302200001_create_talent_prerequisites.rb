class CreateTalentPrerequisites < ActiveRecord::Migration[8.1]
  def change
    create_table :talent_prerequisites do |t|
      t.bigint :node_id,              null: false
      t.bigint :prerequisite_node_id, null: false
      t.timestamps
    end

    add_index :talent_prerequisites, :node_id
    add_index :talent_prerequisites,
              %i[node_id prerequisite_node_id],
              unique: true, name: "idx_talent_prerequisites_unique"
  end
end
