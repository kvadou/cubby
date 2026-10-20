Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resource :session, only: %i[create destroy]
      resources :tokens, only: :create
      delete "tokens/current", to: "tokens#destroy"
      resource :me, only: :show, controller: "me"
      get "evals/latest", to: "evals#latest"

      resources :centers, only: %i[index show] do
        resources :classrooms, only: :index
        resources :enrollments, only: :index
        resources :invoices, only: :index
        resource :ask, only: :create
        resource :analytics, only: :show
        resources :proposed_actions, only: :index do
          member do
            post :approve
            post :dismiss
            post :snooze
          end
        end
      end
    end
  end
end
