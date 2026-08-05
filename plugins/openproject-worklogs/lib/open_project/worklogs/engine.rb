require "open_project/plugins"

module OpenProject
  module Worklogs
    class Engine < ::Rails::Engine
      engine_name :openproject_worklogs

      include OpenProject::Plugins::ActsAsOpEngine

      register "openproject-worklogs",
               author_url: "https://github.com/jmango360/openproject-ee",
               bundled: false,
               settings: false do
        # Global entry permission. Everything beyond "my own time" is additionally
        # filtered against the core per-project time entry permissions
        # (view_time_entries / view_own_time_entries), so granting this alone can
        # never widen what a user gets to see.
        #
        # The `project_module nil` wrapper is not cosmetic: Redmine::Plugin#permission
        # runs immediately, before Zeitwerk is set up, so OpenProject::AccessControl
        # is not resolvable yet. project_module defers the block to a to_prepare hook.
        project_module nil do
          permission :view_worklogs,
                     {
                       "worklogs/timesheets": %i[index grid],
                       "worklogs/cells": %i[create],
                       "worklogs/rows": %i[new create destroy copy_previous],
                       "worklogs/reports": %i[index entries],
                       "worklogs/saved_reports": %i[new create edit update destroy],
                       "worklogs/submissions": %i[new create destroy]
                     },
                     permissible_on: :global,
                     require: :loggedin

          # Deciding on somebody else's week. Separate from view_worklogs on
          # purpose: seeing a timesheet and signing it off are different acts,
          # and most people who may do the first may not do the second.
          permission :approve_worklogs,
                     {
                       "worklogs/approvals": %i[index show update]
                     },
                     permissible_on: :global,
                     require: :loggedin
        end

        menu :global_menu,
             :worklogs,
             { controller: "/worklogs/timesheets", action: :index },
             caption: :"worklogs.label_worklogs",
             after: :my_time_tracking,
             icon: "table",
             if: ->(*) { User.current.allowed_globally?(:view_worklogs) }

        menu :global_menu,
             :worklogs_timesheet,
             { controller: "/worklogs/timesheets", action: :index },
             caption: :"worklogs.timesheet.title",
             parent: :worklogs,
             if: ->(*) { User.current.allowed_globally?(:view_worklogs) }

        menu :global_menu,
             :worklogs_reports,
             { controller: "/worklogs/reports", action: :index },
             caption: :"worklogs.reports.title",
             parent: :worklogs,
             if: ->(*) { User.current.allowed_globally?(:view_worklogs) }

        menu :global_menu,
             :worklogs_approvals,
             { controller: "/worklogs/approvals", action: :index },
             caption: :"worklogs.approval.title",
             parent: :worklogs,
             if: ->(*) { User.current.allowed_globally?(:approve_worklogs) }
      end

      # A locked week has to be locked wherever time is written, not only in
      # this plugin's grid. Both contracts are core's own gate, so the API, the
      # work package dialog and anything added later go through them too.
      patch_with_namespace :TimeEntries, :BaseContract
      patch_with_namespace :TimeEntries, :DeleteContract
    end
  end
end
