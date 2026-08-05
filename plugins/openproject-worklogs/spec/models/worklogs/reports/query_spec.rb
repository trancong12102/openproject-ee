require "spec_helper"

RSpec.describe Worklogs::Reports::Query do
  describe "filters" do
    it "gives every filter in the list a reader and a place in the URL" do
      described_class::FILTERS.each do |name|
        query = described_class.from_params(:"#{name}_ids" => "7,8")

        expect(query.selected_ids(name)).to eq([7, 8])
        expect(query.to_params[:"#{name}_ids"]).to eq([7, 8])
      end
    end

    it "reads a repeated parameter as well as a comma-separated one" do
      expect(described_class.from_params(user_ids: %w[3 4]).user_ids).to eq([3, 4])
    end

    it "drops what is not a number instead of asking the database about it" do
      expect(described_class.from_params(type_ids: "1,,nonsense,1").type_ids).to eq([1])
    end

    it "counts a search as a filter, so the bar can say how many are on" do
      expect(described_class.from_params(text: " invoice ").text).to eq("invoice")
      expect(described_class.from_params(text: "invoice", user_ids: "3").filter_count).to eq(2)
      expect(described_class.from_params({})).not_to be_filters
    end

    # Asked before the join is added, so a report grouped by user never pays
    # for a join it does not read.
    it "knows which filters need the work package table" do
      expect(described_class.from_params(priority_ids: "1")).to be_work_package_filters
      expect(described_class.from_params(assignee_ids: "1")).to be_work_package_filters
      expect(described_class.from_params(user_ids: "1", project_ids: "2"))
        .not_to be_work_package_filters
      # The work package filter itself is on the time entry, not on the join.
      expect(described_class.from_params(work_package_ids: "1")).not_to be_work_package_filters
    end
  end

  describe "#with_period" do
    # Merging a period in would leave the old dates behind, and a preset
    # carrying somebody else's dates is a report showing one span under
    # another span's name.
    it "replaces the period whole, dates included" do
      custom = described_class.from_params(period: "custom", from: "2026-01-01", to: "2026-01-31")
      stepped = custom.with_period(Worklogs::Period.new("this_week"))

      expect(stepped.to_params).not_to include(:from, :to)
      expect(stepped.period).to eq("this_week")
    end

    it "keeps every other filter across the step" do
      query = described_class.from_params(period: "this_month", user_ids: "3", text: "invoice",
                                          rows: %w[project], columns: "month")

      stepped = query.with_period(query.period_object.previous)

      expect(stepped.user_ids).to eq([3])
      expect(stepped.text).to eq("invoice")
      expect(stepped.row_keys).to eq(%w[project])
      expect(stepped.column_key).to eq("month")
      expect(stepped.to_params).to include(period: "month")
    end
  end

  describe "#definition_params" do
    # What a saved report stores, and what two reports are compared on to
    # decide whether one has been edited away from the other.
    it "round-trips, so a report reopened is the report that was saved" do
      query = described_class.from_params(period: "month", from: "2026-08-01", measure: "costs",
                                          rows: %w[user project], columns: "week",
                                          assignee_ids: "5", text: "invoice")

      expect(described_class.from_params(query.definition_params).definition_params)
        .to eq(query.definition_params)
    end

    # `report=<id>` says which saved report the page started from; it changes
    # nothing about the result, so it cannot be part of what is compared.
    it "leaves out which saved report the page came from" do
      query = described_class.from_params(period: "this_month", report: "12")

      expect(query.report_id).to eq(12)
      expect(query.definition_params).not_to include(:report)
      expect(query.to_params).to include(report: 12)
    end
  end
end
