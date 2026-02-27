class AddOptimizedSnapshotLookupIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    # Optimized index for LastEquipmentSnapshotFinderService query
    # Covers: WHERE character_id = ? AND equipment_processed_at > ?
    #         AND all required fields NOT NULL
    #         ORDER BY equipment_processed_at DESC LIMIT 1
    add_index :pvp_leaderboard_entries,
              %i[character_id equipment_processed_at],
              order:         { equipment_processed_at: :desc },
              where:         <<~SQL.squish,
                equipment_processed_at IS NOT NULL#{' '}
                AND specialization_processed_at IS NOT NULL#{' '}
                AND raw_equipment IS NOT NULL#{' '}
                AND raw_specialization IS NOT NULL
              SQL
              name:          "index_entries_for_reusable_snapshot_lookup",
              algorithm:     :concurrently,
              if_not_exists: true
  end
end
