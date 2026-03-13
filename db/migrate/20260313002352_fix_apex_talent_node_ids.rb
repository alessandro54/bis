class FixApexTalentNodeIds < ActiveRecord::Migration[8.1]
  def up
    # Apex talents have 3 rank variants sharing the same translated name and talent_type.
    # Only the highest blizzard_id variant has node_id/display_row/display_col set.
    # This migration copies those values to the orphaned variants so they all appear
    # on the tree as a single grouped node, and sets max_rank = number of variants.
    execute <<~SQL
      WITH apex_main AS (
        -- Find talents that have node_id and a name, acting as the "main" variant
        SELECT t.id AS main_id, t.node_id, t.display_row, t.display_col, t.talent_type,
               tr.value AS talent_name
        FROM talents t
        JOIN translations tr ON tr.translatable_id = t.id
          AND tr.translatable_type = 'Talent'
          AND tr.key = 'name'
          AND tr.locale = 'en_US'
        WHERE t.node_id IS NOT NULL
          AND t.display_row IS NOT NULL
      ),
      orphans AS (
        -- Find talents with same name + talent_type but missing node_id
        SELECT t.id AS orphan_id, am.node_id, am.display_row, am.display_col
        FROM talents t
        JOIN translations tr ON tr.translatable_id = t.id
          AND tr.translatable_type = 'Talent'
          AND tr.key = 'name'
          AND tr.locale = 'en_US'
        JOIN apex_main am ON am.talent_name = tr.value AND am.talent_type = t.talent_type
        WHERE t.node_id IS NULL
          AND t.talent_type = am.talent_type
      )
      UPDATE talents
      SET node_id = orphans.node_id,
          display_row = orphans.display_row,
          display_col = orphans.display_col,
          updated_at = NOW()
      FROM orphans
      WHERE talents.id = orphans.orphan_id
    SQL

    # Now set max_rank = count of variants per node_id (for nodes that gained new variants)
    execute <<~SQL
      WITH node_ranks AS (
        SELECT node_id, COUNT(DISTINCT id) AS variant_count
        FROM talents
        WHERE node_id IS NOT NULL
        GROUP BY node_id
        HAVING COUNT(DISTINCT id) > 1
      )
      UPDATE talents
      SET max_rank = node_ranks.variant_count,
          updated_at = NOW()
      FROM node_ranks
      WHERE talents.node_id = node_ranks.node_id
        AND talents.max_rank != node_ranks.variant_count
    SQL
  end

  def down
    # Not reversible — would need to know which talents were originally orphaned
  end
end
