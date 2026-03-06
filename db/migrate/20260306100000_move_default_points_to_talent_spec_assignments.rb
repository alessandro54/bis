class MoveDefaultPointsToTalentSpecAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :talent_spec_assignments, :default_points, :integer, default: 0, null: false

    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE talent_spec_assignments
          SET default_points = talents.default_points
          FROM talents
          WHERE talent_spec_assignments.talent_id = talents.id
            AND talents.default_points > 0
        SQL
      end
    end

    remove_column :talents, :default_points, :integer, default: 0, null: false
  end
end
