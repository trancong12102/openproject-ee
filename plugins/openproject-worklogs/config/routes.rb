Rails.application.routes.draw do
  # Instance-wide switches. Lives under /admin because that is where an
  # administrator looks for them, not under /worklogs where the users are.
  scope "admin" do
    get "worklogs", to: "worklogs/admin#show", as: :worklogs_settings
    post "worklogs", to: "worklogs/admin#update"
  end

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

    # Who logged their hours and who did not. Singular: there is one table,
    # and which slice of it you are looking at is in the query string.
    get "coverage", to: "coverage#index", as: :coverage

    # A name pinned to a report's parameters. No :index — the list lives in the
    # report's own dropdown, where the person choosing one is already standing.
    resources :saved_reports, only: %i[new create edit update destroy]

    # Handing a week in. Keyed by the week, not by an id: there is at most one
    # submission per person per week, and the grid always knows which week it
    # is looking at.
    resource :submission, only: %i[new create destroy]

    # The other side of it.
    resources :approvals, only: %i[index show update]

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
