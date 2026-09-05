Rails.application.routes.draw do
  devise_for :users
  get "dashboard" => "dashboard#index"
  resource :calendar, only: :show, controller: :calendar
  resources :appointments, only: :create
  resources :appointment_emails, only: :create, path: "appointment-emails"
  # Dependents are exposed as "profiles" in URLs. Controllers, models, and the
  # dependent_* route helpers keep their existing names.
  resources :dependents, path: "profiles" do
    get :avatar, on: :member
    resources :care_team_memberships, path: "care-team", except: :show
  end
  get "profiles/:dependent_id/documents" => "documents#index", as: :dependent_documents
  get "profiles/:dependent_id/documents/new" => "documents#new", as: :new_dependent_document
  post "profiles/:dependent_id/documents" => "documents#create"
  get "profiles/:dependent_id/ai-assistant" => "ai_assistant#index", as: :dependent_ai_assistant
  post "profiles/:dependent_id/ai-assistant" => "ai_assistant#create"
  post "profiles/:dependent_id/ai-assistant/:id/start" => "ai_assistant#start", as: :start_dependent_ai_assistant_query
  get "profiles/:dependent_id/ai-assistant/:id/status" => "ai_assistant#status", as: :status_dependent_ai_assistant_query

  # Legacy /dependents URLs (bookmarks, shared links, sent emails) redirect to
  # /profiles, preserving any query string such as document filters.
  get "dependents(/*path)", to: redirect { |params, request|
    target = "/profiles"
    target += "/#{params[:path]}" if params[:path].present?
    target += "?#{request.query_string}" if request.query_string.present?
    target
  }
  resources :share_events, only: :create
  resources :documents, only: %i[show edit update destroy] do
    get :original, on: :member
  end
  resource :billing, only: :show, controller: :billing
  namespace :billing do
    resource :checkout_session, only: :create
    resource :portal_session, only: :create
  end
  namespace :admin do
    resources :accounts, only: :index
  end
  mount StripeEvent::Engine, at: "/stripe/webhooks"

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "home#index"
end
