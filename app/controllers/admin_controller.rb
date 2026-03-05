class AdminController < ActionController::Base
  before_action :authenticate_admin!

  private

    def authenticate_admin!
      return if session[:admin_authenticated]

      session[:return_to] = request.fullpath
      redirect_to "/admin/login"
    end
end
