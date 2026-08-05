require "spec_helper"

# NOTE: the specs under spec/ need an OpenProject *source* checkout with the dev
# bundle. The runtime image this plugin ships in has no RSpec and a frozen
# bundle, so they cannot be run there — script/verify.rb is the check that runs
# where the plugin actually lives, and it covers the same ground.

RSpec.describe Worklogs::Period do
  describe "presets" do
    it "gives every preset a range in the right order and a label" do
      described_class::PRESETS.each do |name|
        period = described_class.new(name)

        expect(period.range.first).to be <= period.range.last
        expect(period.label).to be_present
      end
    end

    it "reads 'this week' from the configured week start" do
      period = described_class.new("this_week")

      expect(period.range.first).to eq(Worklogs::Week.current.start_date)
      expect(period.range.last).to eq(Worklogs::Week.current.end_date)
    end

    it "makes last month a whole month, not thirty days back" do
      period = described_class.new("last_month")
      last = Time.zone.today.prev_month

      expect(period.range.first).to eq(last.beginning_of_month)
      expect(period.range.last).to eq(last.end_of_month)
    end
  end

  describe "#to_params" do
    # A preset is a question about *now*. A saved "this month" that came back
    # next month still meaning August would be a bookmark that went stale
    # without saying so.
    it "does not pin a preset to the dates it happens to mean today" do
      expect(described_class.new("this_month").to_params).to eq(period: "this_month")
    end

    it "carries the dates of a custom range" do
      period = described_class.new("custom", from: "2026-01-01", to: "2026-01-31")

      expect(period.to_params).to eq(period: "custom", from: "2026-01-01", to: "2026-01-31")
    end
  end

  describe ".from_params" do
    it "falls back rather than raising on a name it does not know" do
      expect(described_class.from_params(period: "nonsense").name).to eq(described_class::DEFAULT)
    end

    it "falls back when a custom range has no dates at all" do
      period = described_class.from_params(period: "custom")

      expect(period.range.first).to be <= period.range.last
    end

    it "puts a reversed range back in order instead of returning an empty one" do
      period = described_class.from_params(period: "custom", from: "2026-03-31", to: "2026-03-01")

      expect(period.range.first).to eq(Date.new(2026, 3, 1))
      expect(period.range.last).to eq(Date.new(2026, 3, 31))
    end

    it "ignores an unparseable date rather than blowing up the page" do
      period = described_class.from_params(period: "custom", from: "not a date", to: "2026-03-01")

      expect(period.range.first).to be <= period.range.last
    end

    # What the month picker sends. It is not an ISO-8601 date and `Date.iso8601`
    # refuses it, so without this every month picked would silently be today's.
    it "accepts the 'YYYY-MM' a month input sends" do
      period = described_class.from_params(period: "month", from: "2026-08")

      expect(period.range.first).to eq(Date.new(2026, 8, 1))
      expect(period.range.last).to eq(Date.new(2026, 8, 31))
    end
  end

  describe "anchored periods" do
    it "means the same span however long after it was written down" do
      period = described_class.anchored("month", Date.new(2026, 8, 14))

      expect(period.to_params).to eq(period: "month", from: "2026-08-14")
      expect(described_class.from_params(period.to_params).range)
        .to eq(Date.new(2026, 8, 1)..Date.new(2026, 8, 31))
    end

    it "anchors a week to the configured week start, not to the anchor date" do
      period = described_class.anchored("week", Date.new(2026, 8, 5))

      expect(period.range.first).to eq(Date.new(2026, 8, 5).beginning_of_week(Worklogs::Week.start_day))
    end

    it "labels itself with the span rather than with a preset name" do
      expect(described_class.anchored("month", Date.new(2026, 8, 14)).label).to include("2026")
      expect(described_class.anchored("quarter", Date.new(2026, 8, 14)).label).to eq("Q3 2026")
      expect(described_class.anchored("year", Date.new(2026, 8, 14)).label).to eq("2026")
    end
  end

  describe "stepping" do
    # The whole reason anchored periods exist: without them "last month" could
    # only ever go back one step, because there is no preset for the month
    # before it.
    it "resolves a preset into the anchored period it names" do
      stepped = described_class.new("this_month").previous

      expect(stepped.name).to eq("month")
      expect(stepped.range).to eq(Time.zone.today.last_month.all_month)
    end

    it "keeps stepping once it is anchored" do
      august = described_class.anchored("month", Date.new(2026, 8, 14))

      expect(august.previous.range.first).to eq(Date.new(2026, 7, 1))
      expect(august.previous.previous.range.first).to eq(Date.new(2026, 6, 1))
      expect(august.next.range.first).to eq(Date.new(2026, 9, 1))
    end

    it "steps a quarter by three months and a year by twelve" do
      expect(described_class.anchored("quarter", Date.new(2026, 8, 14)).previous.range.first)
        .to eq(Date.new(2026, 4, 1))
      expect(described_class.anchored("year", Date.new(2026, 8, 14)).next.range.first)
        .to eq(Date.new(2027, 1, 1))
    end

    it "steps a month across a year boundary rather than wrapping inside it" do
      january = described_class.anchored("month", Date.new(2026, 1, 10))

      expect(january.previous.range).to eq(Date.new(2025, 12, 1)..Date.new(2025, 12, 31))
    end

    # "Last 30 days" and a custom range have no unit but do have a width.
    it "steps a range with no unit by its own length" do
      range = described_class.new("custom", from: "2026-03-01", to: "2026-03-10")

      expect(range.previous.range).to eq(Date.new(2026, 2, 19)..Date.new(2026, 2, 28))
      expect(range.next.range).to eq(Date.new(2026, 3, 11)..Date.new(2026, 3, 20))
    end

    it "knows when the step ahead has not happened yet" do
      expect(described_class.new("this_month")).not_to be_future
      expect(described_class.new("this_month").next).to be_future
    end
  end
end
