class AddAggregationTrackingToPvpSyncCycles < ActiveRecord::Migration[8.1]
  def change
    add_column :pvp_sync_cycles, :expected_aggregation_brackets,  :integer, default: 0, null: false
    add_column :pvp_sync_cycles, :completed_aggregation_brackets, :integer, default: 0, null: false
  end
end
