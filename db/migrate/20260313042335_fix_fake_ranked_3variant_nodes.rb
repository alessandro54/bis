# The earlier migration (fix_fake_ranked_talent_max_rank) only fixed 2-variant
# fake-ranked nodes. This catches the remaining 18 nodes with 3 variants and
# max_rank=3 where no character ever invests rank > 1. These are not truly
# ranked — they're different spells sharing the same name (e.g. "Fist of Justice").
#
# Sets max_rank=1 so the frontend stops treating them as ranked nodes.
class FixFakeRanked3variantNodes < ActiveRecord::Migration[8.1]
  def up
    fake_node_ids = execute(<<~SQL).map { |r| r["node_id"] }
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

    return if fake_node_ids.empty?

    truly_fake = fake_node_ids.select do |node_id|
      talent_ids = execute("SELECT id FROM talents WHERE node_id = #{node_id}").map { |r| r["id"] }
      !execute("SELECT 1 FROM character_talents WHERE talent_id IN (#{talent_ids.join(",")}) AND rank > 1 LIMIT 1").any?
    end

    if truly_fake.any?
      result = execute("UPDATE talents SET max_rank = 1 WHERE node_id IN (#{truly_fake.join(",")}) AND max_rank > 1")
      say "Fixed #{result.cmd_tuples} talents across #{truly_fake.size} fake-ranked nodes (set max_rank=1)"
    end
  end

  def down
    # Not reversible
  end
end
