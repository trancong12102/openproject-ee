Rails.application.routes.draw do
  namespace :worklogs do
    root to: "timesheets#index"

    # Fragment endpoint the grid re-fetches after a core time entry dialog
    # closes — cheaper and less jarring than reloading the whole page.
    get "grid", to: "timesheets#grid"

    resources :reports, only: %i[index] do
      collection do
        # The entries behind one figure in the pivot.
        get :entries
      end
    end

    # A name pinned to a report's parameters. No :index — the list lives in the
    # report's own dropdown, where the person choosing one is already standing.
    resources :saved_reports, only: %i[new create edit update destroy]

    resources :cells, only: %i[create]

    resources :rows, only: %i[new create destroy] do
      collection do
        post :copy_previous
      end
    end

    # Fingerprinted, immutable plugin assets served straight from the gem.
    get "assets/:digest/:filename",
        to: "assets#show",
        as: :asset,
        format: false,
        constraints: { filename: /[\w-]+\.(?:css|js)/ }
  end
end
