Rails.application.routes.draw do
  devise_for :users
  get "dashboard" => "dashboard#index"
  resources :dependents
  get "dependents/:dependent_id/documents" => "documents#index", as: :dependent_documents
  get "dependents/:dependent_id/documents/new" => "documents#new", as: :new_dependent_document
  post "dependents/:dependent_id/documents" => "documents#create"
  get "dependents/:dependent_id/ai-assistant" => "ai_assistant#index", as: :dependent_ai_assistant
  resources :dependents, only: [] do
    resources :care_team_memberships, path: "care-team", except: :show
  end
  resources :documents, only: %i[show destroy]

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "home#index"
end
