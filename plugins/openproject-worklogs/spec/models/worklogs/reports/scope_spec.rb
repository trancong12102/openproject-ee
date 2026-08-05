require "spec_helper"

RSpec.describe Worklogs::Reports::Scope do
  shared_let(:project) { create(:project) }
  shared_let(:viewer) do
    create(:user,
           global_permissions: %i[view_worklogs],
           member_with_permissions: { project => %i[log_time view_time_entries view_work_packages] })
  end
  shared_let(:assignee) { create(:user, member_with_permissions: { project => %i[view_work_packages] }) }
  shared_let(:version) { create(:version, project:) }
  shared_let(:urgent) { create(:priority, name: "Urgent") }

  shared_let(:assigned) do
    create(:work_package, project:, assigned_to: assignee, priority: urgent, version:)
  end
  shared_let(:unassigned) { create(:work_package, project:, assigned_to: nil) }

  let(:today) { Time.zone.today }

  def entry(work_package:, comments: "", hours: 1.0)
    create(:time_entry, user: viewer, project:, work_package:, spent_on: today, hours:, comments:)
  end

  def entries_for(params)
    query = Worklogs::Reports::Query.from_params({ period: "this_month" }.merge(params))

    described_class.new(query:, viewer:).relation.to_a
  end

  describe "the work package filter" do
    # Deliberately on the time entry rather than on the joined row: it has to
    # hold whether or not anything else asked for the join.
    it "matches the entries logged on that work package and no others" do
      mine = entry(work_package: assigned)
      entry(work_package: unassigned)

      expect(entries_for(work_package_ids: assigned.id.to_s)).to eq([mine])
    end

    it "does not pick up time logged on the project itself" do
      entry(work_package: nil)

      expect(entries_for(work_package_ids: assigned.id.to_s)).to be_empty
    end
  end

  describe "the work package attribute filters" do
    before { entry(work_package: assigned) }

    it "filters by priority" do
      expect(entries_for(priority_ids: urgent.id.to_s).size).to eq(1)
      expect(entries_for(priority_ids: (urgent.id + 1000).to_s)).to be_empty
    end

    it "filters by version" do
      expect(entries_for(version_ids: version.id.to_s).size).to eq(1)
    end

    it "filters by assignee" do
      expect(entries_for(assignee_ids: assignee.id.to_s).size).to eq(1)
    end
  end

  describe "'unassigned'" do
    # "Nobody" is a legitimate answer to "assigned to whom", travelling under
    # the id nobody has.
    it "means a work package with no assignee" do
      nobodys = entry(work_package: unassigned)
      entry(work_package: assigned)

      expect(entries_for(assignee_ids: described_class::UNASSIGNED.to_s)).to eq([nobodys])
    end

    # Without the entity guard the left join would leave the assignee null for
    # an entry that has no work package at all, and every hour logged on a
    # project or a meeting would answer to every "unassigned" report.
    it "does not mean a time entry with no work package" do
      entry(work_package: nil)

      expect(entries_for(assignee_ids: described_class::UNASSIGNED.to_s)).to be_empty
    end

    it "can be asked for beside real people" do
      nobodys = entry(work_package: unassigned)
      theirs = entry(work_package: assigned)

      expect(entries_for(assignee_ids: "#{described_class::UNASSIGNED},#{assignee.id}"))
        .to contain_exactly(nobodys, theirs)
    end
  end

  describe "the comment search" do
    it "matches part of a comment, whatever the case" do
      found = entry(work_package: assigned, comments: "Invoice 4021 reviewed")
      entry(work_package: assigned, comments: "Standup")

      expect(entries_for(text: "invoice")).to eq([found])
    end

    # A % typed into a search box is a character somebody is looking for, not
    # an instruction to match everything.
    it "treats a wildcard as the character it looks like" do
      literal = entry(work_package: assigned, comments: "100% done")
      entry(work_package: assigned, comments: "Standup")

      expect(entries_for(text: "%")).to eq([literal])
      expect(entries_for(text: "0%")).to eq([literal])
    end
  end

  describe "what it is built on" do
    # Core's own permission scope. The plugin narrows it and never widens it,
    # so a report cannot show a row the viewer could not have found in core.
    it "cannot see another project's time, filter or no filter" do
      elsewhere = create(:project)
      create(:time_entry, user: create(:user), project: elsewhere,
                          work_package: create(:work_package, project: elsewhere),
                          spent_on: today, hours: 4.0)
      mine = entry(work_package: assigned)

      expect(entries_for({})).to eq([mine])
    end

    it "stops at the period's edges" do
      entry(work_package: assigned)

      expect(entries_for(period: "last_month")).to be_empty
    end
  end
end
