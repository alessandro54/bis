class FixApexVariantSpecAssignments < ActiveRecord::Migration[8.1]
  def up
    # Apex nodes have 3 talent variants (same node_id, max_rank=4) but only
    # the variant returned by the Blizzard tree API gets a TalentSpecAssignment.
    # This ensures all 3 variants are assigned to every spec that uses the node.
    execute <<~SQL
      INSERT INTO talent_spec_assignments (talent_id, spec_id, default_points, created_at, updated_at)
      SELECT missing.talent_id, existing.spec_id, existing.default_points, NOW(), NOW()
      FROM (
        -- All talents on apex nodes (3 variants, max_rank=4)
        SELECT t.id AS talent_id, t.node_id
        FROM talents t
        WHERE t.node_id IS NOT NULL
          AND t.max_rank = 4
          AND t.node_id IN (
            SELECT node_id FROM talents
            WHERE node_id IS NOT NULL AND max_rank = 4
            GROUP BY node_id HAVING COUNT(DISTINCT id) = 3
          )
      ) missing
      JOIN (
        -- Existing spec assignments for sibling talents on the same node
        SELECT DISTINCT tsa.spec_id, tsa.default_points, t2.node_id
        FROM talent_spec_assignments tsa
        JOIN talents t2 ON t2.id = tsa.talent_id
        WHERE t2.node_id IS NOT NULL AND t2.max_rank = 4
      ) existing ON existing.node_id = missing.node_id
      WHERE NOT EXISTS (
        SELECT 1 FROM talent_spec_assignments tsa2
        WHERE tsa2.talent_id = missing.talent_id
          AND tsa2.spec_id = existing.spec_id
      )
    SQL
  end

  def down
    # Not reversible — cannot determine which assignments were added
  end
end
