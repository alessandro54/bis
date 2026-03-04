# frozen_string_literal: true

Rails.application.configure do
  config.lograge.enabled = true

  # Keep original Rails log for ActiveRecord queries in dev
  config.lograge.keep_original_rails_log = Rails.env.development?

  # Production: JSON logs for aggregation (ELK, Datadog, etc.)
  # Development: key=value with colors
  config.lograge.formatter = if Rails.env.production?
                               Lograge::Formatters::Json.new
                             else
                               Lograge::Formatters::KeyValue.new
                             end

  config.lograge.custom_options = lambda do |event|
    extras = {}
    extras[:time] = Time.at(event.time).utc.iso8601 rescue nil
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
      host: controller.request.host,
      request_id: controller.request.request_id,
      remote_ip: controller.request.remote_ip
    }
  end
end
