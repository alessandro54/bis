namespace :db do
  # Pull the production primary database from a Dokku server and restore locally.
  #
  # Required env vars (add to .env):
  #   DOKKU_SSH_HOST  — server IP, e.g. "178.156.204.200"
  #   DOKKU_SSH_USER  — unix user, e.g. "alessandro"
  #   DOKKU_DB        — Dokku postgres service name, e.g. "wow_meta_production"
  #
  # Optional:
  #   DOKKU_SSH_ALIAS — SSH config alias (e.g. "wow-meta") — skips host/user if set
  #
  # Usage:
  #   bundle exec rails db:pull
  #
  desc "Pull production DB from Dokku and restore locally (primary only)"
  task pull: :environment do
    return if Rails.env.production? # safety check


    db_name  = ENV.fetch("DOKKU_DB") { abort "Set DOKKU_DB in .env" }
    dump     = "/tmp/wow_bis_prod.sql"
    local    = ActiveRecord::Base.configurations.find_db_config("development").database
    ssh_host = ENV["DOKKU_SSH_ALIAS"] || begin
      host = ENV.fetch("DOKKU_SSH_HOST") { abort "Set DOKKU_SSH_HOST in .env" }
      user = ENV.fetch("DOKKU_SSH_USER") { abort "Set DOKKU_SSH_USER in .env" }
      "#{user}@#{host}"
    end

    # Tables with live PvP data that change every sync cycle.
    # Excluded: items, translations, talents, enchantments — managed locally.
    live_tables = %w[
      pvp_seasons
      pvp_sync_cycles
      pvp_leaderboards
      pvp_leaderboard_entries
      characters
      character_items
      character_talents
      pvp_meta_item_popularity
      pvp_meta_enchant_popularity
      pvp_meta_gem_popularity
      pvp_meta_talent_popularity
    ]

    full = ENV["DB_PULL_FULL"] == "1"
    table_flags = full ? "" : live_tables.map { |t| "-t #{t}" }.join(" ")
    mode        = full ? "full" : "live tables only"

    puts "→ Exporting #{db_name} from #{ssh_host} (#{mode})..."
    container_cmd = "sudo docker exec \\$(sudo docker ps --filter name=#{db_name} -q) " \
                    "pg_dump -U postgres --no-acl --no-owner -F p #{table_flags} #{db_name}"
    system("ssh #{ssh_host} \"#{container_cmd}\" > #{dump}") || abort("Export failed")
    puts "  Dump saved (#{(File.size(dump) / 1024.0 / 1024.0).round(1)} MB)"

    puts "→ Restoring into local database '#{local}'..."
    # Strip settings unsupported by older local PostgreSQL versions (e.g. transaction_timeout added in PG17)
    system("sed -i '' '/transaction_timeout/d' #{dump}")
    system("psql -d #{local} -f #{dump} > /dev/null") || abort("Restore failed")

    File.delete(dump)
    puts "✓ Done. Local database '#{local}' now mirrors production."
  end
end
