# Pin npm packages by running ./bin/importmap

pin "application"
pin "theme_toggle"
pin "request_panel_state"
pin "detail_slider"
pin "@rails/actioncable", to: "https://cdn.jsdelivr.net/npm/@rails/actioncable@8.0.0/app/assets/javascripts/actioncable.esm.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/channels", under: "channels"
