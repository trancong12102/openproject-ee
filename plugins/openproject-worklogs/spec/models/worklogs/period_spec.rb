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
  end
end
