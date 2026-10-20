Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resource :session, only: %i[create destroy]
      resources :tokens, only: :create
      delete "tokens/current", to: "tokens#destroy"
      resource :demo_session, only: %i[show create]
      resource :me, only: :show, controller: "me"
      get "evals/latest", to: "evals#latest"

      # Parents (mobile): scoped to the signed-in user's family.
      scope "family", module: "parent", as: "family" do
        get "/", to: "families#show"
        resources :children, only: [] do
          resources :attendance, only: :index, controller: "attendances"
        end
        resources :messages, only: :index do
          post :read, on: :member
        end
        resources :invoices, only: :index
      end

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
