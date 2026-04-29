# Gateway hero talents (Halo, Void Torrent, etc.) appear under "class_talents"
# in the Blizzard character specialization endpoint even though they are hero
# talents. UpsertFromRawSpecializationService was calling update_all with
# talent_type: "class" on these blizzard_ids, overwriting the correct "hero"
# classification set by SyncTreeService.
#
# This migration restores the correct hero classification using node_id grouping:
# gateway/apex hero nodes have multiple variant talents sharing the same node_id
# and all sharing the same talent_type. If any variant on a node is currently
# 'hero', all siblings that were downgraded to 'class' or 'spec' should also be
# 'hero'. This is safe because the fix_apex_talent_node_ids migration already
# ensured all apex variants share the same node_id and original talent_type.
#
# After this migration, UpsertFromRawSpecializationService has been patched with
# a `where.not(talent_type: "hero")` guard so this regression cannot recur.
class FixHeroTalentTypeDowngrade < ActiveRecord::Migration[8.0]
  def up
    result = execute(<<~SQL)
      UPDATE talents
      SET talent_type = 'hero',
          updated_at  = NOW()
      WHERE node_id IN (
        -- Nodes where at least one variant is correctly classified as hero
        SELECT DISTINCT node_id
        FROM talents
        WHERE talent_type = 'hero'
          AND node_id IS NOT NULL
      )
      AND talent_type != 'hero'
    SQL

    say "Restored hero classification for #{result.cmd_tuples} downgraded gateway talent(s)"
  end

  def down
    # Not safely reversible — we don't know which were wrongly downgraded
  end
end
