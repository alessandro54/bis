namespace :pvp do
  # == Sync ==

  # Clears equipment_last_modified on all characters so the next sync ignores
  # Blizzard's 304 Not Modified responses and forces a full re-fetch, then
  # enqueues SyncCurrentSeasonLeaderboardsJob to kick off the pipeline.
  desc "Force a full equipment re-sync by clearing Last-Modified timestamps, then enqueue the sync job"
  task force_sync: :environment do
    count = Character.where.not(equipment_last_modified: nil).count
    # rubocop:disable Rails/SkipsModelValidations
    Character.update_all(equipment_last_modified: nil)
    # rubocop:enable Rails/SkipsModelValidations
    puts "Cleared equipment_last_modified for #{count} characters."
    Pvp::SyncCurrentSeasonLeaderboardsJob.perform_later
    puts "Enqueued SyncCurrentSeasonLeaderboardsJob."
  end

  # Finds characters present in the DB who have never had equipment processed
  # (no character_items rows) and enqueues them in batches for a fresh sync.
  # Useful after adding characters manually or after a partial import.
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

  # Clears the TTL snapshot timestamp and equipment fingerprints for every
  # non-private character, then re-enqueues all of them in batches.
  # Use when you need a clean slate — e.g. after a schema change or DB import.
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

  # == Talents ==

  # Runs SyncTreeService in force mode, which re-fetches all talent trees from
  # Blizzard and removes stale spec assignments no longer present in the API.
  # Run after a major patch or when talent data looks out of date.
  desc "Re-sync talent trees from Blizzard, removing stale spec assignments"
  task sync_talents: :environment do
    puts "Syncing talent trees (force)..."
    result = Blizzard::Data::Talents::SyncTreeService.call(force: true)
    if result.success?
      puts "Done — talents: #{result.context[:talents]}, edges: #{result.context[:edges]}"
    else
      puts "Failed: #{result.error}"
    end
  end

  # Clears specialization_processed_at on all current-season leaderboard entries
  # so the next character sync re-processes talent loadouts from scratch, then
  # enqueues all affected characters. Use after a talent tree re-sync or when
  # talent data is stale.
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

  # Detects characters in the current season leaderboard whose specialization was
  # processed but have zero character_talents — their data was silently lost.
  # Clears their loadout codes and re-enqueues them. After jobs complete, run
  # pvp:reaggregate_talents to rebuild the talent meta.
  desc "Find characters with missing talent data, clear their loadout codes, and re-sync"
  task sanitize_talents: :environment do
    batch_size = ENV.fetch("PVP_SYNC_BATCH_SIZE", 50).to_i
    season     = PvpSeason.current

    affected_char_ids = PvpLeaderboardEntry
      .joins(:pvp_leaderboard)
      .where(pvp_leaderboards: { pvp_season: season })
      .where.not(specialization_processed_at: nil)
      .where.not(character_id: CharacterTalent.select(:character_id).distinct)
      .distinct
      .pluck(:character_id)

    if affected_char_ids.empty?
      puts "No characters with missing talent data found. All good."
      next
    end

    puts "Found #{affected_char_ids.size} characters with missing talents."

    # rubocop:disable Rails/SkipsModelValidations
    Character.where(id: affected_char_ids).update_all(spec_talent_loadout_codes: nil)

    updated = PvpLeaderboardEntry
      .joins(:pvp_leaderboard)
      .where(pvp_leaderboards: { pvp_season: season })
      .where(character_id: affected_char_ids)
      .update_all(specialization_processed_at: nil)
    # rubocop:enable Rails/SkipsModelValidations

    puts "Reset specialization_processed_at for #{updated} leaderboard entries."
    puts "Enqueueing re-sync jobs..."

    enqueued = 0
    affected_char_ids.each_slice(batch_size) do |batch|
      Pvp::SyncCharacterBatchJob.perform_later(character_ids: batch)
      enqueued += batch.size
    end

    puts "Done. #{enqueued} characters queued across #{(enqueued.to_f / batch_size).ceil} jobs."
    puts "Run `rails pvp:reaggregate_talents` after jobs complete."
  end

  # Runs TalentAggregationService directly for the current season and increments
  # the meta cache version key. Use after sanitize_talents or any manual talent
  # data fix to rebuild pvp_meta_talent_popularity without a full sync cycle.
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

  # == Data ==

  # Blanks stat_pcts on every character so percentile rankings are recomputed
  # from scratch on the next sync. Use after importing a new dataset or changing
  # the stat percentile calculation logic.
  desc "Clear stat_pcts on all characters so they are recomputed on next sync"
  task clear_stat_pcts: :environment do
    count = Character.where.not(stat_pcts: {}).count
    # rubocop:disable Rails/SkipsModelValidations
    Character.update_all(stat_pcts: {})
    # rubocop:enable Rails/SkipsModelValidations
    puts "Cleared stat_pcts for #{count} characters. Run pvp:force_sync to repopulate."
  end

  # Removes TalentSpecAssignment rows for spec-type talents that fewer than 3
  # characters of that spec actually use. These are cross-spec leakage artifacts
  # caused by shared class talents appearing in multiple spec trees.
  desc "Remove spurious cross-spec TalentSpecAssignment rows (spec-type, <3 character uses)"
  task sanitize_spec_assignments: :environment do
    removed = 0
    TalentSpecAssignment.joins(:talent).where(talents: { talent_type: "spec" }).find_each do |tsa|
      if CharacterTalent.where(spec_id: tsa.spec_id, talent_id: tsa.talent_id).count < 3
        tsa.destroy!
        removed += 1
      end
    end
    puts "Removed #{removed} spurious spec TalentSpecAssignment rows."
  end

  # Enqueues BuildAggregationsJob to rebuild item, enchant, gem, and talent
  # popularity tables for the current season. Use after a data fix when you
  # don't want to wait for the next full sync cycle.
  desc "Rebuild all PvP meta aggregations for the current season"
  task build_aggregations: :environment do
    puts "Enqueuing BuildAggregationsJob..."
    Pvp::BuildAggregationsJob.perform_later
    puts "Done."
  end

  # == Queue ==

  # Deletes all SolidQueue jobs that have a finished_at timestamp. Safe to run
  # at any time — only removes completed jobs, not pending or running ones.
  desc "Delete all finished SolidQueue jobs"
  task clear_finished_jobs: :environment do
    count = SolidQueue::Job.where.not(finished_at: nil).count
    SolidQueue::Job.where.not(finished_at: nil).delete_all
    puts "Deleted #{count} finished jobs."
  end
end
