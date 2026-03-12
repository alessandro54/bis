module Admin
  class BaseController < ActionController::Base
    before_action :require_admin

    private

      def require_admin
        return if session[:admin_authenticated]

        session[:return_to] = request.fullpath
        redirect_to admin_login_path
      end
  end
end
