Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  get "api-docs" => "api_docs#index"

  # Defines the root path route ("/")
  # root "posts#index"
  #
  namespace :api do
    namespace :v1 do
      resources :characters, only: [ :index ]
      get "characters/:region/:realm/:name", to: "characters#show", as: :character_profile

      namespace :pvp do
        scope ":season/:region", as: "season_region_bracket" do
          resources :leaderboards, only: [ :show ], param: :bracket
        end

        namespace :meta do
          resources :items, only: [ :index ]
          resources :enchants, only: [ :index ]
          resources :gems, only: [ :index ]
          resources :specs, only: %i[index show]
          resources :talents, only: [ :index ]
          get :class_distribution, to: "class_distributions#show"
          get :top_players, to: "top_players#index"
          get :stat_priority, to: "stat_priority#show"
        end
      end
    end
  end

  get "/admin/login",    to: "admin/sessions#new", as: :admin_login
  post "/admin/login",   to: "admin/sessions#create"
  delete "/admin/logout", to: "admin/sessions#destroy", as: :admin_logout

  mount MissionControl::Jobs::Engine, at: "/jobs"
  mount_avo

  match "*unmatched", to: "errors#not_found", via: :all, constraints: ->(req) { req.path.start_with?("/api/") }
end
