Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "rulebook#index"

  get "rulebook",      to: "rulebook#index", as: :rulebook
  get "rulebook/show", to: "rulebook#show",  as: :rulebook_show

  get  "rule_search",         to: "rule_search#index",   as: :rule_search
  get  "rule_search/search",  to: "rule_search#search",  as: :rule_search_search
  get  "rule_search/preview", to: "rule_search#preview", as: :rule_search_preview

  get    "rule_agent",          to: "rule_agent#index",          as: :rule_agent
  post   "rule_agent/messages", to: "rule_agent#create_message", as: :rule_agent_messages
  post   "rule_agent/new",      to: "rule_agent#new_chat",       as: :new_rule_agent_chat
  delete "rule_agent",          to: "rule_agent#clear"

  get "flashcards", to: "flashcards#index", as: :flashcards

  resources :documents, only: [:index, :new, :create, :show, :destroy, :edit, :update] do
    resource :flashcards, only: [:show, :create]
  end

  mount MissionControl::Jobs::Engine, at: "/jobs"

  # Turbo Streams over Action Cable
  mount ActionCable.server => "/cable"
end
