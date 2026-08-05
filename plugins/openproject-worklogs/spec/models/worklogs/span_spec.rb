require "spec_helper"

RSpec.describe Worklogs::Span do
  before { allow(Setting).to receive(:start_of_week).and_return(1) }

  describe ".from_params" do
    it "reads a month out of the URL" do
      span = described_class.from_params(span: "month", date: "2026-08-14")

      expect(span).to eq(Worklogs::Month.containing(Date.new(2026, 8, 1)))
    end

    # A week is the default span, so /worklogs?date=… stays the URL it has
    # always been and every link that predates months still works.
    it "reads a week when nothing says otherwise" do
      span = described_class.from_params(date: "2026-08-14")

      expect(span).to eq(Worklogs::Week.containing(Date.new(2026, 8, 14)))
      expect(span.to_params).to eq(date: span.to_param)
    end

    it "answers a typo with the ordinary view rather than an error" do
      expect(described_class.from_params(span: "fortnight", date: "2026-08-14"))
        .to eq(Worklogs::Week.containing(Date.new(2026, 8, 14)))
      expect(described_class.from_params({})).to eq(Worklogs::Week.current)
    end
  end

  describe ".switch" do
    it "is a no-op when the span is already that kind" do
      week = Worklogs::Week.containing(Date.new(2026, 8, 14))

      expect(described_class.switch(week, "week")).to be(week)
    end

    # Switching keeps you where you were standing: the button says "month",
    # not "this month".
    it "widens to the month the week was in" do
      week = Worklogs::Week.containing(Date.new(2026, 3, 30))

      expect(described_class.switch(week, "month"))
        .to eq(Worklogs::Month.containing(Date.new(2026, 3, 1)))
    end

    it "narrows to the week the month started in" do
      march = Worklogs::Month.containing(Date.new(2026, 3, 1))

      expect(described_class.switch(march, "week"))
        .to eq(Worklogs::Week.containing(Date.new(2026, 3, 1)))
    end

    # Narrowing the month you are living in should land on the week you are
    # living in, not on the 1st — that is the sheet you came to fill in.
    it "narrows the current month to the current week" do
      expect(described_class.switch(Worklogs::Month.current, "week"))
        .to eq(Worklogs::Week.current)
    end
  end
end
