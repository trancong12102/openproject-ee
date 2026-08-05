require "spec_helper"

RSpec.describe Worklogs::Team::Sheet do
  shared_let(:project) { create(:project) }
  shared_let(:manager) do
    create(:user, firstname: "Mai", lastname: "Manager",
                  global_permissions: %i[view_worklogs view_worklogs_coverage],
                  member_with_permissions: { project => %i[log_time view_time_entries
                                                           view_work_packages] })
  end
  shared_let(:worker) do
    create(:user, firstname: "Wanda", lastname: "Worker",
                  member_with_permissions: { project => %i[log_own_time view_own_time_entries] })
  end
  shared_let(:idler) do
    create(:user, firstname: "Ida", lastname: "Idler",
                  member_with_permissions: { project => %i[log_own_time view_own_time_entries] })
  end
  shared_let(:work_package) { create(:work_package, project:) }
  shared_let(:development) { create(:time_entry_activity, name: "Development") }
  shared_let(:testing) { create(:time_entry_activity, name: "Testing") }

  let(:monday) { Date.new(2026, 8, 3) }
  let(:week) { Worklogs::Week.containing(monday) }

  def query(**overrides)
    Worklogs::Team::Query.from_params({ date: monday.iso8601 }.merge(overrides))
  end

  def sheet(viewer: manager, **overrides)
    described_class.new(query: query(**overrides), viewer:)
  end

  def log(user:, on:, hours: 2.0, activity: development)
    create(:time_entry, user:, project:, work_package:, activity:, spent_on: on, hours:)
  end

  # The Wednesday of that week: what is owed "by now", and therefore what
  # counts as a gap, is a question about today.
  before do
    allow(Setting).to receive(:start_of_week).and_return(1)
    travel_to(Date.new(2026, 8, 5))
  end

  after { travel_back }

  describe "the rows" do
    before { log(user: worker, on: monday, hours: 3.0) }

    it "is one line per person, one column per day" do
      expect(sheet.dates).to eq(week.dates)
      expect(sheet.rows.map(&:user)).to eq([worker])
      expect(sheet.rows.first.on(monday)).to eq(3.0)
    end

    # Default list is the people with something on it; the empty row is only
    # worth a line when you have asked to see everybody.
    it "leaves out the people with nothing until asked for everyone" do
      expect(sheet.rows.map(&:user)).not_to include(idler)
      expect(sheet(scope: "everyone").rows.map(&:user)).to include(idler, manager)
    end

    it "adds a person's days up to their total, and everyone's to the footer" do
      log(user: manager, on: monday + 1, hours: 5.0)
      built = sheet

      expect(built.rows.sum(&:logged)).to eq(8.0)
      expect(built.total).to eq(8.0)
      expect(built.daily_total(monday)).to eq(3.0)
      expect(built.daily_total(monday + 1)).to eq(5.0)
    end

    it "orders by name by default and by hours when asked" do
      log(user: manager, on: monday, hours: 9.0)

      expect(sheet.rows.map(&:user)).to eq([manager, worker])
      expect(sheet(sort: "hours").rows.map(&:user)).to eq([manager, worker])
      expect(sheet(sort: "hours").rows.map(&:logged)).to eq([9.0, 3.0])
    end
  end

  describe "what the viewer may see" do
    # Core's own scope. The plugin narrows it and never widens it.
    it "shows nothing of a project the viewer has no time permission in" do
      elsewhere = create(:project)
      stranger = create(:user, member_with_permissions: { elsewhere => %i[log_own_time] })
      create(:time_entry, user: stranger, project: elsewhere,
                          work_package: create(:work_package, project: elsewhere),
                          spent_on: monday, hours: 4.0)

      expect(sheet(scope: "everyone").rows.find { |row| row.user == stranger }.logged).to eq(0)
    end

    it "is one line — their own — for somebody who may only see their own time" do
      log(user: worker, on: monday)

      expect(sheet(viewer: worker, scope: "everyone").rows.map(&:user)).to eq([worker])
    end
  end

  describe "the balance" do
    before { log(user: worker, on: monday, hours: 3.0) }

    # Measured against what was owed by today: on a Wednesday the rest of the
    # week is not yet owed.
    it "counts only the days that have already happened as owed" do
      row = sheet.rows.first

      expect(row.capacity).to eq(40.0)
      expect(row.expected).to eq(24.0)
      expect(row.difference).to eq(-21.0)
    end

    it "reads utilisation against the whole span, not against today" do
      expect(sheet.rows.first.utilization).to eq(8)
    end
  end

  describe "the day markers" do
    before { log(user: worker, on: monday, hours: 3.0) }

    it "calls a weekend nobody's working day" do
      expect(sheet.non_working?(week.end_date)).to be(true)
      expect(sheet.non_working?(monday)).to be(false)
    end

    # A gap is an empty working day that has already happened. Tomorrow is not
    # a gap, and neither is a Sunday.
    it "marks only an empty working day that is already behind us" do
      row = sheet.rows.first

      expect(row.gap?(monday)).to be(false)
      expect(row.gap?(monday + 1)).to be(true)
      expect(row.gap?(monday + 3)).to be(false)
      expect(row.gap?(week.end_date)).to be(false)
      expect(row.off?(week.end_date)).to be(true)
    end
  end

  describe "opening a person up" do
    before do
      log(user: worker, on: monday, hours: 2.0, activity: development)
      log(user: worker, on: monday + 1, hours: 1.0, activity: testing)
    end

    it "adds nothing until they are expanded" do
      expect(sheet.rows.first.details).to be_empty
      expect(sheet.rows.first).not_to be_expanded
    end

    # Splitting by activity as well as work package, like the personal sheet:
    # two hours of Development and one of Testing are two different facts.
    it "shows what they worked on, one line per work package and activity" do
      opened = sheet(expand: [worker.id]).rows.first

      expect(opened.details.size).to eq(2)
      expect(opened.details.sum(&:total)).to eq(opened.logged)
      expect(opened.details.map { |detail| detail.activity.name }).to contain_exactly("Development", "Testing")
    end

    it "puts each detail's hours under the day they were logged on" do
      detail = sheet(expand: [worker.id]).rows.first.details
                 .find { |row| row.activity == development }

      expect(detail.cell(monday).hours).to eq(2.0)
      expect(detail.cell(monday + 1).hours).to eq(0)
    end

    it "filters the detail lines with the sheet" do
      opened = sheet(expand: [worker.id], activity_ids: [testing.id]).rows.first

      expect(opened.details.map { |detail| detail.activity }).to eq([testing])
      expect(opened.logged).to eq(1.0)
    end
  end
end
