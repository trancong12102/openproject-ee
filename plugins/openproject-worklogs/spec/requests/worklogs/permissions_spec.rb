require "spec_helper"

RSpec.describe "Worklogs permissions", :webmock do
  shared_let(:keeper) { create(:user, global_permissions: %i[view_worklogs]) }
  shared_let(:manager) do
    create(:user, global_permissions: %i[view_worklogs view_worklogs_coverage])
  end
  shared_let(:approver) do
    create(:user, global_permissions: %i[view_worklogs approve_worklogs])
  end
  shared_let(:admin) { create(:admin) }

  before do
    Setting.plugin_openproject_worklogs = { "approvals_enabled" => true }
    Worklogs::Settings.invalidate!
  end

  after do
    Setting.plugin_openproject_worklogs = Worklogs::Settings::DEFAULTS.dup
    Worklogs::Settings.invalidate!
  end

  # Keeping your own timesheet and looking at everybody else's gaps are
  # different acts, and the whole reason coverage has its own permission.
  describe "the coverage page" do
    it "is closed to somebody who may only keep their own week" do
      login_as keeper
      get "/worklogs/coverage"

      expect(response).to have_http_status(:forbidden)
    end

    it "is open to somebody holding view_worklogs_coverage" do
      login_as manager
      get "/worklogs/coverage"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "the approvals queue" do
    it "is closed without approve_worklogs" do
      login_as manager
      get "/worklogs/approvals"

      expect(response).to have_http_status(:forbidden)
    end

    it "is open to an approver" do
      login_as approver
      get "/worklogs/approvals"

      expect(response).to have_http_status(:ok)
    end

    # Off means gone, not hidden: the URL has to close too, or the button is the
    # only thing that was ever enforcing it.
    it "is gone entirely when approvals are switched off" do
      Setting.plugin_openproject_worklogs = { "approvals_enabled" => false }
      Worklogs::Settings.invalidate!
      login_as approver
      get "/worklogs/approvals"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the settings page" do
    it "is administrators only, whatever else somebody holds" do
      login_as approver
      get "/admin/worklogs"

      expect(response).to have_http_status(:forbidden)
    end

    it "is open to an administrator" do
      login_as admin
      get "/admin/worklogs"

      expect(response).to have_http_status(:ok)
    end

    it "casts what it is given before storing it" do
      login_as admin
      post "/admin/worklogs", params: { approvals_enabled: "1", reminder_weekday: "99",
                                        reminder_hour: "17", reminder_tolerance: "-3" }

      stored = Setting.plugin_openproject_worklogs
      expect(stored["approvals_enabled"]).to be(true)
      expect(stored["reminder_weekday"]).to eq(Worklogs::Settings::DEFAULTS["reminder_weekday"])
      expect(stored["reminder_hour"]).to eq(17)
      expect(stored["reminder_tolerance"]).to eq(0)
    end
  end

  describe "the timesheet" do
    it "is closed to anonymous users" do
      get "/worklogs"

      expect(response).to have_http_status(:found)
    end

    it "is open to anybody holding view_worklogs" do
      login_as keeper
      get "/worklogs"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "assets" do
    # An immutable response has to actually be immutable: answering a stale
    # digest with the current file would leave a proxy holding today's CSS
    # against yesterday's URL for a year.
    it "serves the current digest and refuses any other" do
      login_as keeper
      current = OpenProject::Worklogs::Assets.path("worklogs.css")

      get current
      expect(response).to have_http_status(:ok)

      get "/worklogs/assets/deadbeefcafe/worklogs.css"
      expect(response).to have_http_status(:not_found)
    end
  end
end
