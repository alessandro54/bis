namespace :pvp_sync do
  desc "Force a full equipment re-sync by clearing Last-Modified timestamps, then enqueue the sync job"
  task force: :environment do
    count = Character.where.not(equipment_last_modified: nil).count
    # rubocop:disable Rails/SkipsModelValidations
    Character.update_all(equipment_last_modified: nil)
    # rubocop:enable Rails/SkipsModelValidations
    puts "Cleared equipment_last_modified for #{count} characters."

    Pvp::SyncCurrentSeasonLeaderboardsJob.perform_later
    puts "Enqueued SyncCurrentSeasonLeaderboardsJob."
  end
end
