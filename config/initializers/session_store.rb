# config/initializers/session_store.rb
Rails.application.config.session_store :cookie_store,
  key:       "_wow_meta_session",
  same_site: :lax,
  secure:    Rails.env.production?
