require "spec_helper"

RSpec.describe Worklogs::Month do
  subject(:month) { described_class.containing(Date.new(2026, 8, 14)) }

  it "covers the whole calendar month whatever day it was asked about" do
    expect(month.start_date).to eq(Date.new(2026, 8, 1))
    expect(month.end_date).to eq(Date.new(2026, 8, 31))
    expect(month.length).to eq(31)
  end

  # Everything above a span takes a week or a month and never asks which, so
  # the day Week grows a method Month has not got is the day a page 500s.
  it "answers every question a week answers" do
    expect(Worklogs::Week.instance_methods(false) - described_class.instance_methods(false))
      .to be_empty
  end

  it "names itself as a month, so a page can ask without a type check" do
    expect(month.kind).to eq("month")
    expect(month).to be_month
    expect(month).not_to be_week
  end

  describe "#weeks" do
    # Which weeks a month contains depends on where a week starts, and that is
    # an instance setting. Pinned here so the dates below mean something.
    before { allow(Setting).to receive(:start_of_week).and_return(1) }

    # A submission covers a whole week or none of it. A month that only listed
    # the weeks wholly inside it would be silent about the first and last few
    # days it is drawing.
    it "includes the weeks that spill over both ends" do
      weeks = month.weeks

      expect(weeks.first.include?(Date.new(2026, 8, 1))).to be(true)
      expect(weeks.last.include?(Date.new(2026, 8, 31))).to be(true)
      expect(weeks.first.start_date).to be < month.start_date
    end

    it "leaves no gap between one week and the next" do
      month.weeks.each_cons(2) do |earlier, later|
        expect(later.start_date).to eq(earlier.end_date + 1)
      end
    end

    # June 2026 begins on a Monday: no week hangs off the front of it.
    it "does not add a week in front of a month that starts on the week start" do
      june = described_class.containing(Date.new(2026, 6, 10))

      expect(june.weeks.first.start_date).to eq(Date.new(2026, 6, 1))
    end
  end

  describe "stepping" do
    it "steps by whole months, across the year boundary" do
      expect(month.next.start_date).to eq(Date.new(2026, 9, 1))
      expect(described_class.containing(Date.new(2026, 1, 20)).previous.start_date)
        .to eq(Date.new(2025, 12, 1))
    end

    it "does not shorten February by stepping through a 31-day month" do
      expect(described_class.containing(Date.new(2026, 1, 31)).next.end_date)
        .to eq(Date.new(2026, 2, 28))
    end
  end

  describe ".from_param" do
    it "round-trips through its own parameter" do
      expect(described_class.from_param(month.to_param)).to eq(month)
      expect(month.to_params).to eq(date: "2026-08-01", span: "month")
    end

    it "accepts the 'YYYY-MM' a month input sends" do
      expect(described_class.from_param("2026-08")).to eq(month)
    end

    # The URL is user-editable; the answer to a typo should be the ordinary
    # view rather than an error page.
    it "falls back to this month on anything it cannot read" do
      expect(described_class.from_param("nonsense")).to eq(described_class.current)
      expect(described_class.from_param(nil)).to eq(described_class.current)
      expect(described_class.from_param("today")).to eq(described_class.current)
    end
  end
end
