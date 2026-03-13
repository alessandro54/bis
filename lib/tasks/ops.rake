namespace :ops do
  # Shared SSH helper — reuses the same Dokku deploy key as db:pull.
  def dokku_ssh(cmd)
    ssh_host = ENV.fetch("DOKKU_SSH_HOST") { abort "Set DOKKU_SSH_HOST in .env" }
    ssh_key  = File.expand_path("~/.ssh/dokku_deploy")
    "ssh -i #{ssh_key} dokku@#{ssh_host} #{cmd}"
  end

  def dokku_app
    ENV.fetch("DOKKU_APP") { abort "Set DOKKU_APP in .env (e.g. wow-meta)" }
  end

  desc "Pull production DB and restart cache (db:pull + cache:clear + app restart)"
  task refresh: :environment do
    Rake::Task["db:pull"].invoke
    Rake::Task["ops:cache:clear"].invoke
    Rake::Task["ops:restart"].invoke
    puts "✓ Refresh complete."
  end

  desc "Restart the Dokku app (zero-downtime if checks enabled)"
  task restart: :environment do
    puts "→ Restarting #{dokku_app}..."
    system(dokku_ssh("ps:restart #{dokku_app}")) || abort("Restart failed")
    puts "✓ App restarted."
  end

  namespace :cache do
    desc "Clear the SolidCache store on the remote production app"
    task clear: :environment do
      puts "→ Clearing SolidCache on #{dokku_app}..."
      system(dokku_ssh("run #{dokku_app} bin/rails runner 'Rails.cache.clear'")) || abort("Cache clear failed")
      puts "✓ Cache cleared."
    end
  end
end
