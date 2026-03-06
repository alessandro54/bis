class AdminController < ActionController::Base
  http_basic_authenticate_with(
    name:     "admin",
    password: Rails.application.credentials.admin_password
  )
end
