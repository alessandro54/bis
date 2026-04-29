# Gateway hero talents (Halo, Void Torrent, etc.) appear under "class_talents"
# in the Blizzard character specialization endpoint even though they are hero
# talents. UpsertFromRawSpecializationService was calling update_all with
# talent_type: "class" on these blizzard_ids, overwriting the correct "hero"
# classification set by SyncTreeService.
#
# Two categories of affected talents:
#
# 1. Nodes where at least one variant is still correctly classified as "hero" but
#    sibling variants on the same node_id were downgraded to "class"/"spec".
#    Fixed by: restoring hero for all siblings sharing that node_id.
#
# 2. Fully-downgraded gateway nodes — every variant was downgraded to "class",
#    so there is no surviving "hero" sibling on the node.  These gateway nodes
#    are identifiable by their node_ids sitting inside a run of hero-tree
#    node_ids (≥ 9 of the 11 nearest node_ids belong to hero talents).
#    Currently confirmed: node_id 94697 (Halo, Shadow/Holy Priest) and
#    node_id 94684 (Void Torrent, Shadow Priest).
#
# After this migration, UpsertFromRawSpecializationService has been patched with
# a `where.not(talent_type: "hero")` guard so this regression cannot recur.
class FixHeroTalentTypeDowngrade < ActiveRecord::Migration[8.0]
  # node_ids of gateway/apex talents that are fully downgraded (no hero sibling survives).
  # Halo sits at node_id 94697; Void Torrent at 94684.  Both are surrounded by
  # Shadow/Holy Priest hero-tree node_ids (94677–94703).
  FULLY_DOWNGRADED_GATEWAY_NODE_IDS = [ 94697, 94684 ].freeze

  def up
    # Pass 1: restore siblings whose node_id still has at least one hero variant.
    result1 = execute(<<~SQL)
      UPDATE talents
      SET talent_type = 'hero',
          updated_at  = NOW()
      WHERE node_id IN (
        SELECT DISTINCT node_id
        FROM talents
        WHERE talent_type = 'hero'
          AND node_id IS NOT NULL
      )
      AND talent_type != 'hero'
    SQL

    # Pass 2: restore fully-downgraded gateway nodes (no hero sibling survives).
    node_ids_sql = FULLY_DOWNGRADED_GATEWAY_NODE_IDS.join(", ")
    result2 = execute(<<~SQL)
      UPDATE talents
      SET talent_type = 'hero',
          updated_at  = NOW()
      WHERE node_id IN (#{node_ids_sql})
        AND talent_type != 'hero'
    SQL

    total = result1.cmd_tuples + result2.cmd_tuples
    say "Restored hero classification for #{total} downgraded gateway talent(s) " \
        "(#{result1.cmd_tuples} via surviving sibling, #{result2.cmd_tuples} via known gateway node_ids)"
  end

  def down
    # Not safely reversible — we don't know which were wrongly downgraded
  end
end
