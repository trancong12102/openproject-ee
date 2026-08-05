require "spec_helper"

RSpec.describe Worklogs::SubmissionService do
  shared_let(:project) { create(:project) }
  shared_let(:owner) { create(:user, member_with_permissions: { project => %i[log_own_time view_own_time_entries] }) }
  shared_let(:approver) do
    create(:user, global_permissions: %i[view_worklogs approve_worklogs])
  end
  shared_let(:work_package) { create(:work_package, project:) }

  let(:week) { Worklogs::Week.current }
  let!(:entry) do
    create(:time_entry, user: owner, project:, work_package:, spent_on: week.start_date, hours: 3.5)
  end

  before do
    Setting.plugin_openproject_worklogs = { "approvals_enabled" => true,
                                            "lock_approved_periods" => true }
    Worklogs::Settings.invalidate!
    Worklogs::PeriodLock.invalidate!
  end

  after do
    Setting.plugin_openproject_worklogs = Worklogs::Settings::DEFAULTS.dup
    Worklogs::Settings.invalidate!
    Worklogs::PeriodLock.invalidate!
  end

  describe "#submit" do
    subject(:submission) { described_class.new(actor: owner).submit(user: owner, week:) }

    it "records the week as submitted" do
      expect(submission.errors).to be_empty
      expect(submission.status).to eq("submitted")
      expect(submission.period_start).to eq(week.start_date)
      expect(submission.period_end).to eq(week.end_date)
    end

    # An approval records what the week contains. Permissions must not be able
    # to change that number, so the total is read unfiltered.
    it "records the real total, not the actor's view of it" do
      create(:time_entry, user: owner, project:, spent_on: week.start_date, hours: 2.0)

      expect(submission.hours).to eq(5.5)
    end

    it "leaves a trail entry in the same transaction" do
      expect(submission.events.map(&:action)).to eq(%w[submitted])
    end

    it "refuses to submit somebody else's week" do
      other = described_class.new(actor: approver).submit(user: owner, week:)

      expect(other.errors).not_to be_empty
      expect(Worklogs::Submission.count).to eq(0)
    end
  end

  describe "locking" do
    before { described_class.new(actor: owner).submit(user: owner, week:) }

    it "refuses a change through core's own contract" do
      Worklogs::PeriodLock.invalidate!
      result = TimeEntries::UpdateService.new(user: owner, model: entry.reload).call(hours: 4.0)

      expect(result).to be_failure
      expect(entry.reload.hours).to eq(3.5)
    end

    it "refuses a delete too" do
      Worklogs::PeriodLock.invalidate!

      expect(TimeEntries::DeleteService.new(user: owner, model: entry.reload).call).to be_failure
      expect(TimeEntry.exists?(entry.id)).to be(true)
    end

    # Moving time *into* a closed week is the same act as changing it, and is
    # the one an implementation that only guards the old date lets through.
    it "refuses to move an entry into the closed week" do
      outside = create(:time_entry, user: owner, project:, spent_on: week.start_date - 7, hours: 1.0)
      Worklogs::PeriodLock.invalidate!

      result = TimeEntries::UpdateService.new(user: owner, model: outside)
                                         .call(spent_on: week.start_date)

      expect(result).to be_failure
    end

    it "lets the week go again once locking is switched off" do
      Setting.plugin_openproject_worklogs = { "approvals_enabled" => true,
                                              "lock_approved_periods" => false }
      Worklogs::Settings.invalidate!
      Worklogs::PeriodLock.invalidate!

      expect(TimeEntries::UpdateService.new(user: owner, model: entry.reload).call(hours: 4.0))
        .to be_success
    end
  end

  describe "deciding" do
    let!(:submission) { described_class.new(actor: owner).submit(user: owner, week:) }

    it "records who decided and when, and keeps the trail" do
      described_class.new(actor: approver).approve(submission, note: "fine")

      expect(submission.reload.status).to eq("approved")
      expect(submission.decided_by).to eq(approver)
      expect(submission.events.map(&:action)).to eq(%w[submitted approved])
    end

    it "keeps withdrawn, rejected and reopened as separate events" do
      described_class.new(actor: approver).reject(submission, note: "not yet")
      described_class.new(actor: owner).submit(user: owner, week:)
      described_class.new(actor: approver).approve(submission.reload)
      described_class.new(actor: approver).reopen(submission.reload)

      expect(submission.reload.events.map(&:action))
        .to eq(%w[submitted rejected submitted approved reopened])
    end

    it "refuses self-approval unless the instance allows it" do
      self_approver = create(:user, global_permissions: %i[view_worklogs approve_worklogs])
      own = described_class.new(actor: self_approver).submit(user: self_approver, week:)

      expect(own.decidable_by?(self_approver)).to be(false)

      Setting.plugin_openproject_worklogs = { "approvals_enabled" => true,
                                              "allow_self_approval" => true }
      Worklogs::Settings.invalidate!

      expect(own.decidable_by?(self_approver)).to be(true)
    end

    it "only lets an approver reopen an approved week" do
      described_class.new(actor: approver).approve(submission)

      expect(submission.reload.reopenable_by?(owner)).to be(false)
      expect(submission.reopenable_by?(approver)).to be(true)
    end
  end
end
