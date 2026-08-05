module Worklogs
  module CoverageHelper
    include Worklogs::TimesheetHelper

    def worklogs_coverage_href(query, overrides = {})
      worklogs_coverage_path(query.merge(overrides).to_params)
    end

    def worklogs_coverage_export_href(query, format = "csv")
      worklogs_coverage_path(query.to_params.merge(format:))
    end

    # A percentage nobody is owed anything for is not 0% and not 100%; it is
    # not a percentage.
    def worklogs_utilization(value)
      return "—" if value.nil?

      "#{value}%"
    end

    def worklogs_signed_hours(value)
      value = value.to_f.round(2)
      return worklogs_duration(0) if value.zero?

      "#{value.negative? ? '−' : '+'}#{worklogs_duration(value.abs)}"
    end

    # Each dropdown is its own GET form and has to carry the rest of the query
    # with it, or applying one filter would reset every other.
    def worklogs_coverage_hidden_fields(query, except: [])
      excluded = Array(except).map(&:to_sym)

      safe_join(query.to_params.except(*excluded).flat_map do |name, value|
        Array(value).map do |single|
          hidden_field_tag("#{name}#{'[]' if value.is_a?(Array)}", single, id: nil)
        end
      end)
    end
  end
end
