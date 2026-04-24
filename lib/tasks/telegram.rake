namespace :telegram do
  desc "Send deploy notification to Telegram (called by Dokku postdeploy)"
  task notify_deploy: :environment do
    rev = ENV.fetch("GIT_REV", `git rev-parse --short HEAD 2>/dev/null`.strip.presence || "unknown")
    TelegramNotifier.send("🚀 <b>Deployed</b> — <code>#{rev}</code> · #{Time.current.strftime('%H:%M UTC')}")
  end
end
