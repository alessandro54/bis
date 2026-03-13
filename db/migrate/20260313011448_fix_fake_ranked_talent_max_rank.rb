class FixFakeRankedTalentMaxRank < ActiveRecord::Migration[8.1]
  def up
    # Fix "fake ranked" nodes: 2 variants sharing the same name and node_id,
    # but no character ever invests rank > 1. These are two different spells
    # that happen to share a name, NOT true multi-rank talents.
    # Set their max_rank to 1 so the frontend doesn't show rank bars.
    execute <<~SQL
      UPDATE talents
      SET max_rank = 1
      WHERE max_rank != 1
        AND node_id IN (
          SELECT t.node_id
          FROM talents t
          JOIN translations tr ON tr.translatable_type = 'Talent'
            AND tr.translatable_id = t.id
            AND tr.key = 'name'
            AND tr.locale = 'en_US'
          WHERE t.node_id IS NOT NULL
          GROUP BY t.node_id
          HAVING COUNT(DISTINCT t.id) = 2
             AND COUNT(DISTINCT tr.value) = 1
             AND COALESCE(
               (SELECT MAX(ct.rank)
                FROM character_talents ct
                WHERE ct.talent_id IN (
                  SELECT t2.id FROM talents t2 WHERE t2.node_id = t.node_id
                )), 0
             ) <= 1
        )
    SQL
  end

  def down
    # Not reversible — would need to know original max_rank values
  end
end
