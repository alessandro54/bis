module Admin
  class SessionsController < ActionController::Base
    layout false
    def new; end

    def create
      if params[:password] == Rails.application.credentials.admin_password
        session[:admin_authenticated] = true
        redirect_to session.delete(:return_to) || "/jobs"
      else
        flash.now[:alert] = "Invalid password"
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      session.delete(:admin_authenticated)
      redirect_to "/admin/login"
    end
  end
end
