# For ranked talent nodes (multiple variants sharing the same name and node_id
# with max_rank > 1), only one variant had a TalentSpecAssignment. This means
# the character API only returned 1 variant, preventing the frontend from
# detecting ranked nodes and showing invested rank (e.g. "2/2").
#
# This migration copies spec assignments from the assigned variant to all
# sibling variants that share the same node_id.
class FixRankedVariantSpecAssignments < ActiveRecord::Migration[8.1]
  def up
    # Find ranked nodes: 2+ talents sharing node_id, same name, max_rank > 1
    # Uses polymorphic translations table (translatable_type = 'Talent')
    ranked_node_ids = execute(<<~SQL).map { |r| r["node_id"] }
      SELECT t.node_id
      FROM talents t
      JOIN translations tt
        ON tt.translatable_id = t.id
       AND tt.translatable_type = 'Talent'
       AND tt.locale = 'en_US'
       AND tt.key = 'name'
      WHERE t.max_rank > 1
        AND t.node_id IS NOT NULL
      GROUP BY t.node_id
      HAVING COUNT(*) > 1
         AND COUNT(DISTINCT tt.value) = 1
    SQL

    return if ranked_node_ids.empty?

    created = 0

    ranked_node_ids.each do |node_id|
      talent_ids = execute("SELECT id FROM talents WHERE node_id = #{node_id}").map { |r| r["id"] }

      # Get existing assignments for any variant of this node
      existing = execute(<<~SQL)
        SELECT DISTINCT spec_id, default_points
        FROM talent_spec_assignments
        WHERE talent_id IN (#{talent_ids.join(",")})
      SQL

      existing.each do |row|
        spec_id = row["spec_id"]
        default_points = row["default_points"]

        talent_ids.each do |tid|
          already = execute(<<~SQL).any?
            SELECT 1 FROM talent_spec_assignments
            WHERE talent_id = #{tid} AND spec_id = #{spec_id}
            LIMIT 1
          SQL

          unless already
            execute(<<~SQL)
              INSERT INTO talent_spec_assignments (talent_id, spec_id, default_points, created_at, updated_at)
              VALUES (#{tid}, #{spec_id}, #{default_points}, NOW(), NOW())
            SQL
            created += 1
          end
        end
      end
    end

    say "Created #{created} missing TalentSpecAssignment records for #{ranked_node_ids.size} ranked nodes"
  end

  def down
    # Not reversible — we don't know which assignments existed before
  end
end
