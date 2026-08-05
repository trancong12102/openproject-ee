module Worklogs
  module ReportsHelper
    include Worklogs::TimesheetHelper

    # A measure is rendered by what it is, not by where it sits: hours read as
    # durations, money as money, counts as counts.
    def worklogs_measure(value, measure)
      case measure.to_s
      when "costs" then worklogs_currency(value)
      when "entries" then number_with_delimiter(value.to_i)
      else worklogs_duration(value)
      end
    end

    # Zero is the common case in a pivot, and a table full of "0h" hides the
    # numbers that matter. Cells say nothing instead.
    def worklogs_measure_cell(value, measure)
      return "" if value.to_f.zero?

      worklogs_measure(value, measure)
    end

    def worklogs_currency(value)
      number_to_currency(value.to_f,
                         unit: Setting.costs_currency,
                         format: Setting.costs_currency_format,
                         precision: 2)
    rescue StandardError
      number_with_precision(value.to_f, precision: 2)
    end

    def worklogs_report_path(query, overrides = {})
      worklogs_reports_path(query.merge(overrides).to_params)
    end

    def worklogs_report_csv_path(query)
      worklogs_reports_path(query.to_params.merge(format: :csv))
    end

    # Each filter dropdown is its own GET form, so it has to carry the rest of
    # the report with it or applying one filter would reset every other.
    def worklogs_query_hidden_fields(query, except: [])
      excluded = Array(except).map(&:to_sym)

      safe_join(query.to_params.except(*excluded).flat_map do |name, value|
        Array(value).map do |single|
          hidden_field_tag("#{name}#{'[]' if value.is_a?(Array)}", single, id: nil)
        end
      end)
    end

    # Share of the largest row, for the bar behind each label.
    def worklogs_share(value, maximum)
      return 0 if maximum.to_f.zero?

      [(value.to_f / maximum.to_f * 100).round(1), 100].min
    end
  end
end
