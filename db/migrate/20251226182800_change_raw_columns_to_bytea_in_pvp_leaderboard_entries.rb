class ChangeRawColumnsToByteaInPvpLeaderboardEntries < ActiveRecord::Migration[8.1]
  # This migration converts jsonb columns to bytea for zstd compression
  # Existing data will be migrated: JSON -> compressed binary
  #
  # Benefits:
  # - ~60% storage reduction
  # - Faster I/O (less data to read/write)
  # - Reduced memory usage
  #
  # The CompressedJson concern handles transparent compression/decompression

  def up
    # Add new binary columns
    add_column :pvp_leaderboard_entries, :raw_equipment_compressed, :binary
    add_column :pvp_leaderboard_entries, :raw_specialization_compressed, :binary

    # Migrate existing data in batches (compress existing JSON)
    say_with_time "Compressing existing raw_equipment data" do
      compress_existing_data(:raw_equipment, :raw_equipment_compressed)
    end

    say_with_time "Compressing existing raw_specialization data" do
      compress_existing_data(:raw_specialization, :raw_specialization_compressed)
    end

    # Remove old columns and rename new ones
    remove_column :pvp_leaderboard_entries, :raw_equipment
    remove_column :pvp_leaderboard_entries, :raw_specialization

    rename_column :pvp_leaderboard_entries, :raw_equipment_compressed, :raw_equipment
    rename_column :pvp_leaderboard_entries, :raw_specialization_compressed, :raw_specialization
  end

  def down
    # Add new jsonb columns
    add_column :pvp_leaderboard_entries, :raw_equipment_json, :jsonb
    add_column :pvp_leaderboard_entries, :raw_specialization_json, :jsonb

    # Migrate data back (decompress)
    say_with_time "Decompressing raw_equipment data" do
      decompress_existing_data(:raw_equipment, :raw_equipment_json)
    end

    say_with_time "Decompressing raw_specialization data" do
      decompress_existing_data(:raw_specialization, :raw_specialization_json)
    end

    # Remove compressed columns and rename json ones
    remove_column :pvp_leaderboard_entries, :raw_equipment
    remove_column :pvp_leaderboard_entries, :raw_specialization

    rename_column :pvp_leaderboard_entries, :raw_equipment_json, :raw_equipment
    rename_column :pvp_leaderboard_entries, :raw_specialization_json, :raw_specialization
  end

  private

    def compress_existing_data(source_column, target_column)
      batch_size = 1000
      total = 0

      PvpLeaderboardEntry.where.not(source_column => nil).in_batches(of: batch_size) do |batch|
        updates = batch.pluck(:id, source_column).map do |id, json_data|
          json_string = json_data.is_a?(String) ? json_data : Oj.dump(json_data, mode: :compat)
          compressed = Zstd.compress(json_string, level: 3)
          { id: id, target_column => compressed }
        end

        # Bulk update using raw SQL for performance
        updates.each do |update|
          PvpLeaderboardEntry.where(id: update[:id]).update_all(
            target_column => update[target_column]
          )
        end

        total += batch.size
      end

      total
    end

    def decompress_existing_data(source_column, target_column)
      batch_size = 1000
      total = 0

      PvpLeaderboardEntry.where.not(source_column => nil).in_batches(of: batch_size) do |batch|
        updates = batch.pluck(:id, source_column).map do |id, compressed_data|
          json_string = Zstd.decompress(compressed_data)
          json_data = Oj.load(json_string, mode: :compat)
          { id: id, target_column => json_data }
        end

        updates.each do |update|
          PvpLeaderboardEntry.where(id: update[:id]).update_all(
            target_column => update[target_column]
          )
        end

        total += batch.size
      end

      total
    end
end
