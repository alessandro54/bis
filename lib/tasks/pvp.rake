namespace :pvp do
  desc "Enqueue sync for characters that have no character_items (no loadout processed yet)"
  task sync_missing_loadouts: :environment do
    batch_size = ENV.fetch("PVP_SYNC_BATCH_SIZE", 50).to_i

    ids = Character
      .where(is_private: false)
      .left_joins(:character_items)
      .where(character_items: { id: nil })
      .pluck(:id)

    if ids.empty?
      puts "No characters with missing loadouts found."
      next
    end

    puts "Found #{ids.size} characters without a loadout. Enqueueing in batches of #{batch_size}..."

    enqueued = 0
    ids.each_slice(batch_size) do |batch|
      Pvp::SyncCharacterBatchJob.perform_later(character_ids: batch)
      enqueued += batch.size
    end

    puts "Done. #{enqueued} characters queued across #{(enqueued.to_f / batch_size).ceil} jobs."
  end

  desc "Force re-sync ALL non-private characters: clears TTL/fingerprint guards and enqueues batch jobs"
  task resync_all: :environment do
    batch_size = ENV.fetch("PVP_SYNC_BATCH_SIZE", 50).to_i

    total = Character.where(is_private: false).count
    puts "Resetting sync guards for #{total} characters..."

    # rubocop:disable Rails/SkipsModelValidations
    Character.update_all(
      last_equipment_snapshot_at: nil,
      equipment_fingerprint:      nil
    )
    # rubocop:enable Rails/SkipsModelValidations

    puts "Enqueueing #{(total.to_f / batch_size).ceil} batches of #{batch_size}..."

    enqueued = 0
    Character.where(is_private: false).in_batches(of: batch_size) do |batch|
      ids = batch.pluck(:id)
      Pvp::SyncCharacterBatchJob.perform_later(character_ids: ids)
      enqueued += ids.size
    end

    puts "Done. #{enqueued} characters queued across #{(enqueued.to_f / batch_size).ceil} jobs."
  end
end
