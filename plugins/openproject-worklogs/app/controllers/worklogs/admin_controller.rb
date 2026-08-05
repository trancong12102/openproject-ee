module Worklogs
  # The instance-wide switches. Administrator only, like every other
  # `Setting.plugin_*` page in OpenProject — these decide how the plugin behaves
  # for everybody, which is not a thing to hand out per project.
  class AdminController < ApplicationController
    helper Worklogs::AdminHelper

    before_action :require_admin

    menu_item :worklogs_settings

    layout "admin"

    def show
      @settings = Settings.current
    end

    def update
      Setting.plugin_openproject_worklogs = Settings.sanitise(permitted_params)
      Settings.invalidate!
      PeriodLock.invalidate!

      flash[:notice] = I18n.t(:notice_successful_update)
      redirect_to action: :show
    end

    private

    def permitted_params
      params.permit(*Settings::DEFAULTS.keys)
    end
  end
end
