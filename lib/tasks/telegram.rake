namespace :telegram do
  desc "Send deploy notification to Telegram (called by Dokku postdeploy)"
  task notify_deploy: :environment do
    rev = ENV.fetch("GIT_REV", `git rev-parse --short HEAD 2>/dev/null`.strip.presence || "unknown")
    TelegramNotifier.send("🚀 <b>Deployed</b> — <code>#{rev}</code> · #{Time.current.strftime('%H:%M UTC')}")
  end

  desc "Register bot commands with Telegram (idempotent, run on deploy)"
  task set_commands: :environment do
    commands = [
      { command: "cycle",            description: "Cycle status (progress bar if active)" },
      { command: "status",           description: "Alias for /cycle" },
      { command: "history",          description: "Last 5 completed cycles" },
      { command: "errors",           description: "Job errors in last 24h" },
      { command: "jobs",             description: "Job success rate last 24h" },
      { command: "syncnow",          description: "Trigger a sync immediately" },
      { command: "abort",            description: "Abort a running cycle" },
      { command: "revalidate_cache", description: "Force Next.js cache revalidation" },
      { command: "help",             description: "List all commands" },
    ]
    token = ENV["TELEGRAM_BOT_TOKEN"]
    HTTPX.post(
      "https://api.telegram.org/bot#{token}/setMyCommands",
      json: { commands: commands }
    )
    puts "Telegram commands registered."
  end
end
