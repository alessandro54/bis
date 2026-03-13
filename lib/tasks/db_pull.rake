namespace :db do
  # Pull the production primary database from Dokku via `postgres:export`
  # and restore locally using pg_restore. Connects as dokku@ using the
  # passwordless deploy key at ~/.ssh/dokku_deploy.
  #
  # Required env vars (add to .env):
  #   DOKKU_SSH_HOST — server IP or hostname, e.g. "178.156.204.200"
  #   DOKKU_DB       — Dokku postgres service name, e.g. "wow_meta_production"
  #
  # Usage:
  #   bundle exec rails db:pull
  #
  desc "Pull full production DB from Dokku and restore locally"
  task pull: :environment do
    return if Rails.env.production? # safety check


    db_name  = ENV.fetch("DOKKU_DB") { abort "Set DOKKU_DB in .env" }
    dump     = "/tmp/wow_bis_prod.dump"
    local    = ActiveRecord::Base.configurations.find_db_config("development").database
    ssh_host = ENV.fetch("DOKKU_SSH_HOST") { abort "Set DOKKU_SSH_HOST in .env" }
    ssh_key  = File.expand_path("~/.ssh/dokku_deploy")

    puts "→ Exporting #{db_name} from #{ssh_host}..."
    system("ssh -i #{ssh_key} dokku@#{ssh_host} postgres:export #{db_name} > #{dump}") || abort("Export failed")
    puts "  Dump saved (#{(File.size(dump) / 1024.0 / 1024.0).round(1)} MB)"

    puts "→ Dropping and recreating '#{local}'..."
    system("dropdb --if-exists #{local}") || abort("dropdb failed")
    system("createdb #{local}") || abort("createdb failed")

    puts "→ Restoring into '#{local}'..."
    system("pg_restore --no-acl --no-owner -d #{local} #{dump}")
    # pg_restore returns non-zero on warnings (e.g. extension comments) — verify data loaded
    count = ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM pvp_seasons").first["count"]
    abort("Restore failed — no data found") if count.to_i.zero?

    File.delete(dump)

    # The production dump stamps ar_internal_metadata with environment: "production",
    # which causes Rails to block destructive commands (db:drop, db:reset).
    # Re-stamp it as development so local tooling works normally.
    ActiveRecord::Base.connection.execute(
      "UPDATE ar_internal_metadata SET value = '#{Rails.env}' WHERE key = 'environment'"
    )

    # Ensure the queue database schema is up to date (it's local-only, not pulled
    # from production, but may have been wiped by dropdb/createdb during PG upgrades).
    puts "→ Ensuring queue database schema..."
    system("bundle exec rails db:prepare:queue")

    puts "✓ Done. Local database '#{local}' now mirrors production."
  end
end
