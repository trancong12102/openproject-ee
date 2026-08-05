module Worklogs
  # Naming a report, and handing the name to colleagues.
  #
  # Saving stores parameters, never results: `create` and `update` write down
  # the query the user is looking at, and opening a saved report re-runs it as
  # whoever opened it. Nothing here can widen what a person may see.
  class SavedReportsController < ApplicationController
    include OpTurbo::ComponentStream
    include Worklogs::ReportsHelper

    before_action :require_login
    authorize_with_global_permission :view_worklogs

    before_action :load_query
    before_action :load_saved_report, only: %i[edit update destroy]
    before_action :authorize_edit, only: %i[edit update destroy]

    def new
      @saved_report = SavedReport.new(user: current_user, name: suggested_name, shared: false)

      respond_with_dialog(
        Reports::SaveDialogComponent.new(saved_report: @saved_report, query: @query, mode: :create)
      )
    end

    def create
      @saved_report = SavedReport.new(user: current_user, query: @query, **saved_report_attributes)

      if @saved_report.save
        redirect_to worklogs_saved_report_href(@saved_report), status: :see_other
      else
        rerender_form(mode: :create)
      end
    end

    def edit
      respond_with_dialog(
        Reports::SaveDialogComponent.new(saved_report: @saved_report, query: @query, mode: :update)
      )
    end

    # Two different edits arrive here. Renaming leaves the definition alone;
    # "save changes" overwrites the definition with whatever the page is
    # currently showing and leaves the name alone.
    def update
      @saved_report.assign_attributes(saved_report_attributes)
      @saved_report.query = @query if definition_update?

      if @saved_report.save
        redirect_to worklogs_saved_report_href(@saved_report), status: :see_other
      else
        rerender_form(mode: :update)
      end
    end

    def destroy
      @saved_report.destroy

      redirect_to worklogs_reports_path(@query.definition_params), status: :see_other
    end

    private

    def load_query
      @query = Reports::Query.from_params(params)
    end

    def load_saved_report
      @saved_report = SavedReport.visible(current_user).find(params[:id])
    end

    def authorize_edit
      render_403 unless @saved_report.editable_by?(current_user)
    end

    def definition_update?
      ActiveModel::Type::Boolean.new.cast(params[:definition]).present?
    end

    # Only fields the submitted form actually carried are assigned. "Save
    # changes" posts the definition and nothing else, and must not silently
    # un-share a report just by leaving the checkbox out of its markup.
    def saved_report_attributes
      submitted = params[:worklogs_saved_report]
      return {} if submitted.blank?

      submitted = submitted.permit(:name, :shared) if submitted.respond_to?(:permit)

      {}.tap do |attributes|
        attributes[:name] = submitted[:name] if submitted.key?(:name)
        attributes[:shared] = ActiveModel::Type::Boolean.new.cast(submitted[:shared]).present? if submitted.key?(:shared)
      end
    end

    def rerender_form(mode:)
      update_via_turbo_stream(
        component: Reports::SaveFormComponent.new(saved_report: @saved_report, query: @query, mode:),
        status: :bad_request
      )

      respond_with_turbo_streams
    end

    # A name nobody has to think about: what the report is grouped by, over
    # which period. Renaming it is one field away.
    def suggested_name
      I18n.t("worklogs.reports.saved.suggested_name",
             dimension: @query.row_dimensions.first.label,
             period: @query.period_label)
    end
  end
end
