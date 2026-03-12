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

  # == Health ==

  # Prints per-bracket processing coverage, character availability, and data
  # freshness for the current season's leaderboard entries. Modelled after
  # translations:health — quick visual check that the sync pipeline is healthy.
  #
  # Usage:
  #   bundle exec rails pvp:health
  desc "Print entry processing health for the current season"
  task health: :environment do # rubocop:disable Metrics/BlockLength
    season = PvpSeason.current
    abort "No active season found." unless season

    bar = ->(label, count, total, good: true) {
      pct    = total > 0 ? (count.to_f / total * 100).round(1) : 100.0
      filled = ("█" * (pct / 5).round).ljust(20)
      ok     = good ? count == total : count.zero?
      marker = ok ? "✓" : "✗"
      puts "  #{marker} #{label.ljust(18)} #{filled} #{pct.to_s.rjust(5)}%  (#{count})"
    }

    # --- Header ---
    last_cycle = PvpSyncCycle.where(pvp_season: season).order(created_at: :desc).first

    puts "\nEntry Health — #{season.display_name}"
    if last_cycle
      ts  = last_cycle.completed_at || last_cycle.updated_at
      ago = distance_of_time(Time.current - ts)
      puts "Last sync: #{last_cycle.status} — #{ago} ago " \
           "(#{last_cycle.completed_character_batches}/#{last_cycle.expected_character_batches} batches)"
    end
    puts

    # --- Per-bracket processing ---
    leaderboards = PvpLeaderboard.where(pvp_season: season).order(:bracket, :region)

    overall_total     = 0
    overall_processed = 0

    leaderboards.group_by(&:bracket).each do |bracket, lbs|
      lb_ids = lbs.map(&:id)

      total, fully, eq_only, spec_only, none = PvpLeaderboardEntry
        .where(pvp_leaderboard_id: lb_ids)
        .pick(
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at IS NOT NULL AND specialization_processed_at IS NOT NULL)"),
          Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at IS NOT NULL AND specialization_processed_at IS NULL)"),
          Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at IS NULL AND specialization_processed_at IS NOT NULL)"),
          Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at IS NULL AND specialization_processed_at IS NULL)")
        )
      next if total.zero?

      overall_total     += total
      overall_processed += fully

      regions = lbs.map { |lb| lb.region.upcase }.sort.join(" + ")
      puts "#{bracket} (#{regions}) — #{total} entries"
      bar.call("Fully processed", fully, total)
      bar.call("Equipment only",  eq_only, total, good: false)
      bar.call("Talents only",    spec_only, total, good: false)
      bar.call("Unprocessed",     none, total, good: false)
      puts
    end

    # --- Character health ---
    char_ids = PvpLeaderboardEntry
      .joins(:pvp_leaderboard)
      .where(pvp_leaderboards: { pvp_season: season })
      .distinct
      .pluck(:character_id)

    if char_ids.any?
      total_c, private_c, unavailable_c = Character.where(id: char_ids).pick(
        Arel.sql("COUNT(*)"),
        Arel.sql("COUNT(*) FILTER (WHERE is_private = true)"),
        Arel.sql("COUNT(*) FILTER (WHERE unavailable_until IS NOT NULL AND unavailable_until > NOW())")
      )
      available_c = total_c - private_c - unavailable_c

      puts "Characters — #{total_c} unique"
      bar.call("Available",       available_c, total_c)
      bar.call("Not found (404)", unavailable_c, total_c, good: false)
      bar.call("Private",         private_c, total_c, good: false)
      puts
    end

    # --- Freshness ---
    processed_scope = PvpLeaderboardEntry
      .joins(:pvp_leaderboard)
      .where(pvp_leaderboards: { pvp_season: season })
      .where.not(equipment_processed_at: nil)

    total_p, h1, h6, h24, older = processed_scope.pick(
      Arel.sql("COUNT(*)"),
      Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at > NOW() - INTERVAL '1 hour')"),
      Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at BETWEEN NOW() - INTERVAL '6 hours' AND NOW() - INTERVAL '1 hour')"),
      Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at BETWEEN NOW() - INTERVAL '24 hours' AND NOW() - INTERVAL '6 hours')"),
      Arel.sql("COUNT(*) FILTER (WHERE equipment_processed_at <= NOW() - INTERVAL '24 hours')")
    )

    if total_p&.positive?
      puts "Freshness (equipment) — #{total_p} processed entries"
      bar.call("< 1h ago",  h1, total_p)
      bar.call("1–6h ago",  h6, total_p, good: false)
      bar.call("6–24h ago", h24, total_p, good: false)
      bar.call("> 24h ago", older, total_p, good: false)
      puts
    end

    # --- Summary ---
    if overall_total > 0
      pct = (overall_processed.to_f / overall_total * 100).round(1)
      puts "Overall: #{pct}% fully processed (#{overall_processed}/#{overall_total})"
    end
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

def distance_of_time(seconds)
  seconds = seconds.to_i
  if seconds < 60 then "#{seconds}s"
  elsif seconds < 3_600 then "#{seconds / 60}m"
  elsif seconds < 86_400 then "#{seconds / 3_600}h"
  else "#{seconds / 86_400}d"
  end
end
