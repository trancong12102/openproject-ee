require "spec_helper"

RSpec.describe "Worklogs coverage arithmetic" do
  let(:week) { (Date.new(2026, 1, 5)..Date.new(2026, 1, 11)).to_a }
  let(:bucket) { Worklogs::Coverage::Bucket.new(key: "2026-W02", dates: week) }

  def cell(logged:, capacity: 8.0, expected: capacity, on: bucket)
    Worklogs::Coverage::Cell.new(bucket: on, logged:, capacity:, expected:)
  end

  describe Worklogs::Coverage::Cell do
    it "measures the gap against what was owed, not against the whole capacity" do
      expect(cell(logged: 4.0, capacity: 40.0, expected: 8.0).missing).to eq(4.0)
    end

    # Somebody who logged nothing one week and twelve hours of overtime the next
    # still has an empty week to explain.
    it "does not let overtime read as a negative gap" do
      over = cell(logged: 14.0)

      expect(over.missing).to eq(0)
      expect(over.difference).to eq(6.0)
    end

    it "reads a day with no capacity as off rather than as a gap" do
      off = cell(logged: 0.0, capacity: 0.0, expected: 0.0)

      expect(off.state).to eq(:off)
      expect(off.missing).to eq(0)
      expect(off.utilization).to be_nil
    end

    context "with a bucket that has not happened yet" do
      let(:future) do
        Worklogs::Coverage::Bucket.new(key: "future",
                                       dates: ((Time.zone.today + 30)..(Time.zone.today + 36)).to_a)
      end

      it "reads as 'not yet' while it is empty" do
        expect(cell(logged: 0.0, expected: 0.0, on: future).state).to eq(:future)
      end

      # Time logged ahead of the day it was due is still time logged.
      it "stops reading as 'not yet' the moment something is in it" do
        expect(cell(logged: 4.0, expected: 0.0, on: future).state).not_to eq(:future)
      end
    end
  end

  describe Worklogs::Coverage::Row do
    subject(:row) { described_class.new(user: User.new(id: 1), cells: [short, over]) }

    let(:short) { cell(logged: 2.0) }
    let(:over) { cell(logged: 14.0) }

    it "adds the gaps up rather than netting them off" do
      expect(row.missing).to eq(6.0)
    end

    it "still reports the net balance separately" do
      expect(row.logged).to eq(16.0)
      expect(row.difference).to eq(0)
    end

    it "counts the buckets a gap falls in" do
      expect(row.missing_buckets).to eq(1)
      expect(row).to be_missing
    end

    it "calls a row with nothing at all in it silent, not merely short" do
      empty = described_class.new(user: User.new(id: 1), cells: [cell(logged: 0.0)])

      expect(empty).to be_silent
      expect(row).not_to be_silent
    end
  end

  describe Worklogs::Coverage::Bucket do
    it "clips a part week to the period rather than pretending it is whole" do
      query = Worklogs::Coverage::Query.new(period: "custom", from: "2026-01-07",
                                            to: "2026-01-20", group_by: "week")
      buckets = described_class.build(query)

      expect(buckets.first.start_date).to eq(Date.new(2026, 1, 7))
      expect(buckets.last.end_date).to eq(Date.new(2026, 1, 20))
    end

    it "counts only the days that have already happened as elapsed" do
      current = described_class.new(key: "now",
                                    dates: ((Time.zone.today - 2)..(Time.zone.today + 4)).to_a)

      expect(current.elapsed_dates.last).to eq(Time.zone.today)
      expect(current.elapsed_dates.size).to eq(3)
    end
  end
end
