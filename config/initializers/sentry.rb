# frozen_string_literal: true

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]

  # Only enable in production (no-op if DSN is nil)
  config.enabled_environments = %w[production]

  # Performance monitoring: sample 10% of requests
  config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", 0.1).to_f

  # Send 100% of errors
  config.sample_rate = 1.0

  # Breadcrumbs for debugging context
  config.breadcrumbs_logger = %i[active_support_logger http_logger]

  # Background job integration
  config.excluded_exceptions += [
    "ActionController::RoutingError",
    "ActiveRecord::RecordNotFound"
  ]

  # Tag releases for tracking deploys
  config.release = ENV["GIT_SHA"] || `git rev-parse --short HEAD 2>/dev/null`.strip.presence

  config.enabled_patches = [ :logger ]

  # Enable sending logs to Sentry
  config.enable_logs = true

  # Filter sensitive params
  config.send_default_pii = true
end
