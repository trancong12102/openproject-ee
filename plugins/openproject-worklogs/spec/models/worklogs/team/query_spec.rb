require "spec_helper"

RSpec.describe Worklogs::Team::Query do
  subject(:query) { described_class.from_params(date: "2026-08-05") }

  before { allow(Setting).to receive(:start_of_week).and_return(1) }

  describe ".from_params" do
    it "reads a week by default and a month when asked" do
      expect(query.span).to be_a(Worklogs::Week)
      expect(described_class.from_params(span: "month", date: "2026-08-05").span)
        .to eq(Worklogs::Month.containing(Date.new(2026, 8, 1)))
    end

    it "falls back rather than raising on a scope or order it does not know" do
      odd = described_class.from_params(scope: "nonsense", sort: "nonsense")

      expect(odd.scope).to eq(described_class::DEFAULTS[:scope])
      expect(odd.sort).to eq(described_class::DEFAULTS[:sort])
    end

    it "drops what is not a number instead of asking the database about it" do
      expect(described_class.from_params(user_ids: "3,,nope,3").user_ids).to eq([3])
    end
  end

  describe "#to_params" do
    # A URL should say what is unusual about the page, not restate everything
    # ordinary about it.
    it "leaves the defaults out" do
      expect(query.to_params).to eq(date: "2026-08-03")
    end

    it "carries anything that is not a default" do
      params = query.merge(scope: "everyone", sort: "hours", project_ids: [7]).to_params

      expect(params).to include(scope: "everyone", sort: "hours", project_ids: [7])
    end

    it "round-trips, so a link opens the page it was copied from" do
      full = query.merge(scope: "everyone", sort: "hours", user_ids: [3], expand: [3])

      expect(described_class.from_params(full.to_params).to_params).to eq(full.to_params)
    end
  end

  describe "#with_span" do
    # Merging a span in would leave last month's date under this week's name.
    it "replaces the span whole, dates included" do
      month = query.with_span(Worklogs::Month.containing(Date.new(2026, 3, 10)))

      expect(month.to_params).to include(span: "month", date: "2026-03-01")
      expect(month.with_span(Worklogs::Week.current).to_params).not_to include(:span)
    end

    it "keeps the filters across the step" do
      stepped = query.merge(project_ids: [7], scope: "everyone").with_span(query.span.next)

      expect(stepped.project_ids).to eq([7])
      expect(stepped.scope).to eq("everyone")
    end
  end

  describe "#toggling" do
    let(:user) { build_stubbed(:user, id: 42) }

    it "opens a person up and closes them again" do
      opened = query.toggling(user)

      expect(opened).to be_expanded(user)
      expect(opened.to_params[:expand]).to eq([42])
      expect(opened.toggling(user)).not_to be_expanded(user)
    end

    # Each expansion is a query and another thirty-one columns of markup.
    it "will not open more than the cap" do
      many = described_class.from_params(expand: (1..20).to_a)

      expect(many.expanded_ids.size).to eq(described_class::MAX_EXPANDED)
    end
  end
end
