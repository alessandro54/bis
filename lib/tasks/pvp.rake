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
      last_equipment_snapshot_at:  nil,
      spec_equipment_fingerprints: nil
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

  desc "Reset specialization_processed_at so all characters get their talents re-synced on next run"
  task reset_specialization: :environment do
    batch_size = ENV.fetch("PVP_SYNC_BATCH_SIZE", 50).to_i

    scope = PvpLeaderboardEntry
      .joins(:pvp_leaderboard)
      .where(pvp_leaderboards: { pvp_season: PvpSeason.current })
      .where.not(specialization_processed_at: nil)
    # rubocop:disable Rails/SkipsModelValidations
    updated = scope.update_all(specialization_processed_at: nil)
    # rubocop:enable Rails/SkipsModelValidations

    puts "Reset specialization_processed_at for #{updated} leaderboard entries."
    puts "Enqueueing character batch jobs to re-sync talents..."

    char_ids = PvpLeaderboardEntry
      .joins(:pvp_leaderboard)
      .where(pvp_leaderboards: { pvp_season: PvpSeason.current })
      .joins(:character)
      .where(characters: { is_private: false })
      .distinct
      .pluck(:character_id)

    enqueued = 0
    char_ids.each_slice(batch_size) do |batch|
      Pvp::SyncCharacterBatchJob.perform_later(character_ids: batch)
      enqueued += batch.size
    end

    puts "Done. #{enqueued} characters queued across #{(enqueued.to_f / batch_size).ceil} jobs."
  end

  desc "Re-run talent aggregation for the current season and bust the meta cache"
  task reaggregate_talents: :environment do
    season = PvpSeason.current
    puts "Running TalentAggregationService for season #{season.id}..."
    result = Pvp::Meta::TalentAggregationService.call(season: season)
    if result.success?
      puts "Done. #{result.context[:count]} records upserted."
    else
      puts "Failed: #{result.error}"
    end
    Rails.cache.increment("pvp_meta/version")
    puts "Meta cache busted."
  end
end
