require "spec_helper"

RSpec.describe Worklogs::ReminderService do
  shared_let(:project) { create(:project) }
  shared_let(:behind) do
    create(:user, member_with_permissions: { project => %i[log_own_time] })
  end
  shared_let(:up_to_date) do
    create(:user, member_with_permissions: { project => %i[log_own_time] })
  end

  let(:week) { Worklogs::Week.current.previous }

  before do
    Setting.plugin_openproject_worklogs = { "reminders_enabled" => true }
    Worklogs::Settings.invalidate!

    capacity = Worklogs::Capacity.new(user: up_to_date, week:)
    capacity.working_days.each do |date|
      create(:time_entry, user: up_to_date, project:, spent_on: date,
                          hours: capacity.hours_for(date))
    end
  end

  after do
    Setting.plugin_openproject_worklogs = Worklogs::Settings::DEFAULTS.dup
    Worklogs::Settings.invalidate!
  end

  it "writes to the person who is behind and nobody else" do
    expect(described_class.new(week:).recipients).to include(behind)
    expect(described_class.new(week:).recipients).not_to include(up_to_date)
  end

  # Chasing somebody who did exactly what you asked is how a reminder becomes
  # the mail everybody filters into a folder they never open.
  it "leaves alone anybody who already handed the week in" do
    Worklogs::SubmissionService.new(actor: behind).submit(user: behind, week:)

    expect(described_class.new(week:).recipients).not_to include(behind)
  end

  it "leaves alone anybody within the tolerance" do
    capacity = Worklogs::Capacity.new(user: behind, week:)
    capacity.working_days.each do |date|
      create(:time_entry, user: behind, project:, spent_on: date,
                          hours: capacity.hours_for(date) - 0.05)
    end

    expect(described_class.new(week:, tolerance: 1.0).recipients).not_to include(behind)
    expect(described_class.new(week:, tolerance: 0.0).recipients).to include(behind)
  end

  # The cron only ever asks about last week, where this makes no difference. It
  # matters the moment somebody calls the service by hand.
  it "does not chase anybody for a week that has not happened yet" do
    expect(described_class.new(week: Worklogs::Week.current.next).recipients).to be_empty
  end

  it "does not chase somebody who owed nothing at all" do
    allow_any_instance_of(Worklogs::CapacityCalendar) # rubocop:disable RSpec/AnyInstance
      .to receive(:total_for).and_return(0.0)

    expect(described_class.new(week:).recipients).to be_empty
  end

  describe Cron::WorklogsReminderJob do
    # GoodJob reads its cron table once, at boot, so the schedule cannot come
    # from a setting. The job runs hourly and decides for itself.
    it "does nothing while reminders are off" do
      Setting.plugin_openproject_worklogs = { "reminders_enabled" => false }
      Worklogs::Settings.invalidate!

      expect(described_class.new.send(:due?)).to be(false)
    end

    it "fires only in the configured hour of the configured day" do
      now = Time.zone.now
      Setting.plugin_openproject_worklogs = { "reminders_enabled" => true,
                                              "reminder_weekday" => now.to_date.cwday,
                                              "reminder_hour" => now.hour }
      Worklogs::Settings.invalidate!

      expect(described_class.new.send(:due?)).to be(true)

      Setting.plugin_openproject_worklogs = { "reminders_enabled" => true,
                                              "reminder_weekday" => now.to_date.cwday,
                                              "reminder_hour" => (now.hour + 1) % 24 }
      Worklogs::Settings.invalidate!

      expect(described_class.new.send(:due?)).to be(false)
    end
  end
end
