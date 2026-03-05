require_relative "boot"

require "rails/all"
require_relative "../lib/colorized_log_formatter"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module WowBis
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc
    # config.eager_load_paths << Rails.root.join("extras")

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Gzip compress all responses > 1KB
    config.middleware.use Rack::Deflater

    # Each fiber gets its own ActiveRecord connection checkout,
    # preventing fibers from sharing/corrupting each other's queries.
    config.active_support.isolation_level = :fiber


    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore, key: "_your_app_session"
    config.middleware.use ActionDispatch::Flash
    config.middleware.use Rack::MethodOverride

    config.hosts << "intervals-gently-underground-amber.trycloudflare.com"

    # Lograge: single-line request logs
    config.lograge.enabled = true
    config.lograge.keep_original_rails_log = Rails.env.development?

    config.lograge.formatter = if Rails.env.production?
      Lograge::Formatters::Json.new
    else
      ColorizedLogrageFormatter.new
    end

    config.lograge.custom_options = ->(event) do
      extras = {}
      extras[:time] = Time.current.iso8601
      extras[:host] = event.payload[:host]
      extras[:request_id] = event.payload[:request_id]
      extras[:ip] = event.payload[:remote_ip]

      if event.payload[:exception]
        extras[:exception] = event.payload[:exception].first
        extras[:exception_message] = event.payload[:exception].last
      end

      extras.compact
    end

    config.lograge.custom_payload do |controller|
      {
        host:       controller.request.host,
        request_id: controller.request.request_id,
        remote_ip:  controller.request.remote_ip
      }
    end
  end
end
