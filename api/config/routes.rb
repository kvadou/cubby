Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :centers, only: %i[index show] do
        resources :classrooms, only: :index
        resources :enrollments, only: :index
        resources :invoices, only: :index
        resources :proposed_actions, only: :index
      end
    end
  end
end
