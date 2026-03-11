namespace :fix do
  desc "Re-sync talent trees from Blizzard, removing stale spec assignments"
  task talents: :environment do
    puts "Syncing talent trees (force)..."
    result = Blizzard::Data::Talents::SyncTreeService.call(force: true)
    if result.success?
      puts "Done — talents: #{result.context[:talents]}, edges: #{result.context[:edges]}"
    else
      puts "Failed: #{result.error}"
    end
  end

  desc "Clear stat_pcts on all characters so they are recomputed on next sync"
  task stats: :environment do
    # rubocop:disable Rails/SkipsModelValidations
    count = Character.where.not(stat_pcts: {}).count
    Character.update_all(stat_pcts: {})
    # rubocop:enable Rails/SkipsModelValidations
    puts "Cleared stat_pcts for #{count} characters. Run pvp_sync:force to repopulate."
  end

  desc "Remove spurious cross-spec TalentSpecAssignment rows (spec-type, <3 character uses)"
  task spec_assignments: :environment do
    removed = 0
    TalentSpecAssignment.joins(:talent).where(talents: { talent_type: "spec" }).find_each do |tsa|
      if CharacterTalent.where(spec_id: tsa.spec_id, talent_id: tsa.talent_id).count < 3
        tsa.destroy!
        removed += 1
      end
    end
    puts "Removed #{removed} spurious spec TalentSpecAssignment rows."
  end

  desc "Rebuild all PvP meta aggregations for the current season"
  task aggregations: :environment do
    puts "Enqueuing BuildAggregationsJob..."
    Pvp::BuildAggregationsJob.perform_later
    puts "Done."
  end

  desc "Run all fixes: talents + aggregations"
  task all: :environment do
    Rake::Task["fix:talents"].invoke
    Rake::Task["fix:aggregations"].invoke
  end
end
