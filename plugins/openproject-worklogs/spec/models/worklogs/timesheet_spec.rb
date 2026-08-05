require "spec_helper"

RSpec.describe Worklogs::Timesheet do
  shared_let(:project) { create(:project) }
  shared_let(:other_project) { create(:project) }
  shared_let(:owner) do
    create(:user,
           global_permissions: %i[view_worklogs],
           member_with_permissions: { project => %i[log_own_time view_own_time_entries],
                                      other_project => %i[log_own_time view_own_time_entries] })
  end
  shared_let(:work_package) { create(:work_package, project:) }
  shared_let(:other_work_package) { create(:work_package, project: other_project) }
  shared_let(:development) { create(:time_entry_activity, name: "Development") }
  shared_let(:testing) { create(:time_entry_activity, name: "Testing") }

  let(:month) { Worklogs::Month.containing(Date.new(2026, 8, 14)) }
  let(:first_week) { month.weeks.first }
  let(:last_week) { month.weeks.last }

  def log(on:, hours: 2.0, activity: development, wp: work_package)
    create(:time_entry, user: owner, project: wp.project, work_package: wp,
                        activity:, spent_on: on, hours:)
  end

  def sheet(span: month, **rest)
    described_class.new(user: owner, span:, viewer: owner, **rest)
  end

  before { allow(Setting).to receive(:start_of_week).and_return(1) }

  describe "a month" do
    it "draws a column for every day of the month and nothing either side" do
      expect(sheet.dates.first).to eq(Date.new(2026, 8, 1))
      expect(sheet.dates.last).to eq(Date.new(2026, 8, 31))
      expect(sheet.dates.size).to eq(31)
    end

    it "collects hours from every week it covers into one row" do
      log(on: Date.new(2026, 8, 3), hours: 2.0)
      log(on: Date.new(2026, 8, 24), hours: 3.0)

      expect(sheet.rows.size).to eq(1)
      expect(sheet.total).to eq(5.0)
    end

    it "leaves out time either side of the month, however near" do
      log(on: Date.new(2026, 7, 31))
      log(on: Date.new(2026, 9, 1))

      expect(sheet).to be_empty
      expect(sheet.total).to eq(0)
    end

    # Two hours of Development and one of Testing on the same work package are
    # two different facts, and merging them would make the cell uneditable.
    it "keeps one row per work package and activity" do
      log(on: Date.new(2026, 8, 3), activity: development)
      log(on: Date.new(2026, 8, 3), activity: testing)

      expect(sheet.rows.size).to eq(2)
    end
  end

  # Pins are weekly even when the sheet is a month.
  describe "pinned rows" do
    it "shows a row pinned in any week the month touches" do
      Worklogs::RowPin.create!(user_id: owner.id, week_start: last_week.start_date,
                               entity_type: "WorkPackage", entity_id: work_package.id)

      expect(sheet.rows.map(&:entity)).to eq([work_package])
      expect(sheet.total).to eq(0)
    end

    it "does not draw a second, empty row beside one that has hours" do
      log(on: Date.new(2026, 8, 3), activity: development)
      Worklogs::RowPin.create!(user_id: owner.id, week_start: first_week.start_date,
                               entity_type: "WorkPackage", entity_id: work_package.id,
                               activity_id: development.id)

      expect(sheet.rows.size).to eq(1)
    end
  end

  describe "filters" do
    before do
      log(on: Date.new(2026, 8, 3), activity: development)
      log(on: Date.new(2026, 8, 4), activity: testing, wp: other_work_package)
    end

    it "narrows to a project" do
      expect(sheet(project_ids: [project.id]).rows.map(&:entity)).to eq([work_package])
    end

    it "narrows to an activity" do
      expect(sheet(activity_ids: [testing.id]).rows.map(&:entity)).to eq([other_work_package])
    end

    # Filtering by one project would otherwise still show every row pinned in
    # another one, which reads as the filter having failed.
    it "filters the empty rows too" do
      Worklogs::RowPin.create!(user_id: owner.id, week_start: first_week.start_date,
                               entity_type: "WorkPackage", entity_id: other_work_package.id)

      expect(sheet(project_ids: [project.id]).rows.map(&:entity)).to eq([work_package])
    end

    it "says so, so an empty grid can explain itself" do
      expect(sheet).not_to be_filtered
      expect(sheet(project_ids: [project.id], activity_ids: [testing.id]).filter_count).to eq(2)
    end
  end

  describe "locking a month that is only partly signed off" do
    before do
      Setting.plugin_openproject_worklogs = { "approvals_enabled" => true,
                                              "lock_approved_periods" => true }
      Worklogs::Settings.invalidate!
      Worklogs::PeriodLock.invalidate!

      log(on: first_week.end_date)
      Worklogs::SubmissionService.new(actor: owner).submit(user: owner, week: first_week)
    end

    after do
      Setting.plugin_openproject_worklogs = Worklogs::Settings::DEFAULTS.dup
      Worklogs::Settings.invalidate!
      Worklogs::PeriodLock.invalidate!
    end

    it "closes the days in the submitted week and leaves the rest open" do
      expect(sheet.locked_on?(first_week.end_date)).to be(true)
      expect(sheet.locked_on?(last_week.start_date)).to be(false)
    end

    it "is not a locked sheet while there is still somewhere to put an hour" do
      expect(sheet).to be_any_locked
      expect(sheet).not_to be_locked
    end

    # Asking a month for "the" submission is a question with no answer; the
    # month view lists its weeks instead.
    it "hands over a submission per week, and none for the month itself" do
      expect(sheet.submission).to be_nil
      expect(sheet.submission_for(first_week)).to be_present
      expect(sheet.submission_for(last_week)).to be_nil
      expect(sheet(span: first_week).submission).to be_present
    end
  end
end
