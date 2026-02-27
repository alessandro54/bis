Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
  #
  namespace :api do
    namespace :v1 do
      resources :characters, only: [ :index ]

      namespace :pvp do
        namespace :meta do
          resources :items, only: [ :index ]
          resources :enchants, only: [ :index ]
          resources :gems, only: [ :index ]
          resources :specs, only: %i[index show]
          get :class_distribution, to: "class_distributions#show"
        end
      end
    end
  end

  mount MissionControl::Jobs::Engine, at: "/jobs"
  mount_avo
end
