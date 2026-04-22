class AddPvpSyncCycleToPopularityTables < ActiveRecord::Migration[8.1]
  def change
    # ── pvp_meta_item_popularity ─────────────────────────────────────────
    add_reference :pvp_meta_item_popularity, :pvp_sync_cycle,
                  null: true, index: true, foreign_key: true
    remove_index  :pvp_meta_item_popularity, name: "idx_meta_item_unique"
    add_index     :pvp_meta_item_popularity,
                  %i[pvp_season_id bracket spec_id slot item_id],
                  unique: true, where: "pvp_sync_cycle_id IS NULL",
                  name: "idx_meta_item_unique_no_cycle"
    add_index     :pvp_meta_item_popularity,
                  %i[pvp_sync_cycle_id bracket spec_id slot item_id],
                  unique: true, where: "pvp_sync_cycle_id IS NOT NULL",
                  name: "idx_meta_item_unique_cycle"

    # ── pvp_meta_enchant_popularity ───────────────────────────────────────
    add_reference :pvp_meta_enchant_popularity, :pvp_sync_cycle,
                  null: true, index: true, foreign_key: true
    remove_index  :pvp_meta_enchant_popularity, name: "idx_meta_enchant_unique"
    add_index     :pvp_meta_enchant_popularity,
                  %i[pvp_season_id bracket spec_id slot enchantment_id],
                  unique: true, where: "pvp_sync_cycle_id IS NULL",
                  name: "idx_meta_enchant_unique_no_cycle"
    add_index     :pvp_meta_enchant_popularity,
                  %i[pvp_sync_cycle_id bracket spec_id slot enchantment_id],
                  unique: true, where: "pvp_sync_cycle_id IS NOT NULL",
                  name: "idx_meta_enchant_unique_cycle"

    # ── pvp_meta_gem_popularity ───────────────────────────────────────────
    add_reference :pvp_meta_gem_popularity, :pvp_sync_cycle,
                  null: true, index: true, foreign_key: true
    remove_index  :pvp_meta_gem_popularity, name: "idx_meta_gem_unique"
    add_index     :pvp_meta_gem_popularity,
                  %i[pvp_season_id bracket spec_id slot socket_type item_id],
                  unique: true, where: "pvp_sync_cycle_id IS NULL",
                  name: "idx_meta_gem_unique_no_cycle"
    add_index     :pvp_meta_gem_popularity,
                  %i[pvp_sync_cycle_id bracket spec_id slot socket_type item_id],
                  unique: true, where: "pvp_sync_cycle_id IS NOT NULL",
                  name: "idx_meta_gem_unique_cycle"

    # ── pvp_meta_talent_popularity ────────────────────────────────────────
    add_reference :pvp_meta_talent_popularity, :pvp_sync_cycle,
                  null: true, index: true, foreign_key: true
    remove_index  :pvp_meta_talent_popularity, name: "idx_meta_talent_unique"
    add_index     :pvp_meta_talent_popularity,
                  %i[pvp_season_id bracket spec_id talent_id],
                  unique: true, where: "pvp_sync_cycle_id IS NULL",
                  name: "idx_meta_talent_unique_no_cycle"
    add_index     :pvp_meta_talent_popularity,
                  %i[pvp_sync_cycle_id bracket spec_id talent_id],
                  unique: true, where: "pvp_sync_cycle_id IS NOT NULL",
                  name: "idx_meta_talent_unique_cycle"

    # ── pvp_seasons — live cycle pointer ─────────────────────────────────
    add_reference :pvp_seasons, :live_pvp_sync_cycle,
                  null: true, index: true,
                  foreign_key: { to_table: :pvp_sync_cycles }
  end
end
