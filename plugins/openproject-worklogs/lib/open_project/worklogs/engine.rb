require "open_project/plugins"

module OpenProject
  module Worklogs
    # The plugin's default settings, as a plain literal.
    #
    # They live here, in the file `Redmine::Plugin.register` is called from,
    # rather than on `Worklogs::Settings`, because register runs while this file
    # is being read — before Zeitwerk is set up — so nothing under `app/` is
    # resolvable yet. `Worklogs::Settings::DEFAULTS` points back at this.
    SETTINGS_DEFAULTS = {
      # nil means "follow core". Core's own `hours_per_day` is declared
      # `format: :integer`, so an instance whose day is seven and a half hours
      # has no way to say so there; this one takes a fraction.
      "hours_per_day" => nil,
      "approvals_enabled" => true,
      "lock_approved_periods" => true,
      "allow_self_approval" => false,
      "reminders_enabled" => false,
      "reminder_weekday" => 1,
      "reminder_hour" => 8,
      "reminder_tolerance" => 0.5
    }.freeze

    class Engine < ::Rails::Engine
      engine_name :openproject_worklogs

      include OpenProject::Plugins::ActsAsOpEngine

      register "openproject-worklogs",
               author_url: "https://github.com/jmango360/openproject-ee",
               bundled: false,
               # Reminders are off until somebody turns them on: a plugin that
               # starts mailing everybody the week after an upgrade is a plugin
               # people uninstall.
               settings: { default: OpenProject::Worklogs::SETTINGS_DEFAULTS } do
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

          # Seeing how the whole team is doing is a manager's act, not part of
          # keeping your own timesheet — and unlike the timesheet there is no
          # useful "just me" version of it.
          permission :view_worklogs_coverage,
                     {
                       "worklogs/coverage": %i[index],
                       "worklogs/team": %i[index]
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
             :worklogs_team,
             { controller: "/worklogs/team", action: :index },
             caption: :"worklogs.team.title",
             parent: :worklogs,
             if: ->(*) { User.current.allowed_globally?(:view_worklogs_coverage) }

        menu :global_menu,
             :worklogs_reports,
             { controller: "/worklogs/reports", action: :index },
             caption: :"worklogs.reports.title",
             parent: :worklogs,
             if: ->(*) { User.current.allowed_globally?(:view_worklogs) }

        menu :global_menu,
             :worklogs_coverage,
             { controller: "/worklogs/coverage", action: :index },
             caption: :"worklogs.coverage.title",
             parent: :worklogs,
             if: ->(*) { User.current.allowed_globally?(:view_worklogs_coverage) }

        menu :global_menu,
             :worklogs_approvals,
             { controller: "/worklogs/approvals", action: :index },
             caption: :"worklogs.approval.title",
             parent: :worklogs,
             if: ->(*) { User.current.allowed_globally?(:approve_worklogs) && ::Worklogs::Settings.approvals_enabled? }

        menu :admin_menu,
             :worklogs_settings,
             { controller: "/worklogs/admin", action: :show },
             caption: :"worklogs.label_worklogs",
             icon: "table",
             if: ->(*) { User.current.admin? }
      end

      # Core knows :xls but not :xlsx, and `respond_to { format.xlsx }` on an
      # unregistered format is an ActionController::UnknownFormat. Guarded so
      # that the day core registers it, this quietly steps aside rather than
      # redefining it underneath everybody else.
      # The type is spelled out rather than read off Xlsx::Workbook::CONTENT_TYPE
      # because an initializer runs before autoloading is allowed; the writer's
      # constant is checked against this string in script/verify.rb instead.
      initializer "worklogs.mime_types" do
        if Mime[:xlsx].nil?
          Mime::Type.register("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", :xlsx)
        end
      end

      # Hourly, not weekly: GoodJob reads its cron table once at boot, so a
      # weekly entry would freeze the reminder day and hour into the deployment.
      # The job itself checks the setting and does nothing the other 167 times.
      config.after_initialize do
        Rails.application.config.good_job.cron.merge!(
          "Cron::WorklogsReminderJob": {
            cron: "2 * * * *",
            class: "Cron::WorklogsReminderJob"
          }
        )
      end

      # A locked week has to be locked wherever time is written, not only in
      # this plugin's grid. Both contracts are core's own gate, so the API, the
      # work package dialog and anything added later go through them too.
      patch_with_namespace :TimeEntries, :BaseContract
      patch_with_namespace :TimeEntries, :DeleteContract
    end
  end
end
