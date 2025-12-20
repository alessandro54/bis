Rails.application.config.after_initialize do
  next unless Rails.cache.nil?

  Rails.logger.warn("[cache_store_safeguard] Rails.cache was nil; falling back to :memory_store")
  Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store)
end
