module Worklogs
  module Reports
    # The report as a PDF: the thing that gets attached to an email, signed off
    # on, or filed with an invoice.
    #
    # Figures read the way the screen reads them ("35h 30m", "€1,204.00"), the
    # opposite choice from the CSV and XLS exports — nobody re-sums a PDF, they
    # read it.
    #
    # Landscape, because a pivot with a time axis is wider than it is tall, and
    # built on core's `Exports::PDF::Common::View`, which registers the same
    # Unicode font stack the rest of OpenProject's PDFs use. Prawn's built-in
    # fonts are WinAnsi only, and would raise on the first Vietnamese name.
    class PDFExport
      include ActionView::Helpers::NumberHelper
      include Worklogs::ReportsHelper

      PAGE_LAYOUT = :landscape
      MAX_ROWS = 400

      HEADING_SIZE = 16
      META_SIZE = 8
      TABLE_SIZE = 8

      attr_reader :result, :title

      def initialize(result:, title: nil)
        @result = result
        @title = title.presence || I18n.t("worklogs.reports.title")
      end

      def to_pdf
        view.options.merge!(page_layout: PAGE_LAYOUT, page_size: "A4", margin: 28)
        view.title = title

        write_heading
        write_summary
        write_table
        write_notes
        write_footer

        view.document.render
      end

      private

      def view
        @view ||= Exports::PDF::Common::View.new(User.current.language)
      end

      def pdf = view.document
      def query = result.query
      def data = @data ||= TableData.new(result:)

      def write_heading
        pdf.font_size(HEADING_SIZE) { pdf.text(title, style: :bold) }
        pdf.move_down(4)
        pdf.font_size(META_SIZE) do
          pdf.fill_color("57606a")
          meta_lines.each { |line| pdf.text(line) }
          pdf.fill_color("000000")
        end
        pdf.move_down(10)
      end

      # What was asked, so the answer can be read six weeks later by somebody
      # who was not the one who asked it.
      def meta_lines
        lines = ["#{query.period_label} · #{grouping_summary} · #{measure_label}"]
        lines << "#{I18n.t('worklogs.reports.filters')}: #{filter_summary}" if query.filters?
        lines << "#{I18n.t('worklogs.reports.generated')}: " \
                 "#{Time.zone.now.strftime('%Y-%m-%d %H:%M')} · #{result.viewer.name}"
        lines
      end

      def write_summary
        pdf.font_size(TABLE_SIZE + 2) do
          pdf.text(summary_line, style: :bold)
        end
        pdf.move_down(8)
      end

      def summary_line
        parts = ["#{I18n.t('worklogs.reports.measures.hours')}: #{worklogs_duration(result.totals[:hours])}",
                 "#{I18n.t('worklogs.reports.measures.entries')}: #{number_with_delimiter(result.totals[:entries])}"]
        parts << "#{I18n.t('worklogs.reports.measures.costs')}: #{worklogs_currency(result.totals[:costs])}" if costs?

        parts.join("   ·   ")
      end

      def costs?
        result.scope.costs_visible?
      end

      def write_table
        if data.rows.empty?
          pdf.text(I18n.t("worklogs.reports.blank_description"), size: TABLE_SIZE + 1)
          return
        end

        pdf.table(table_rows, table_options) do |table|
          table.row(0).font_style = :bold
          table.row(0).background_color = "f6f8fa"
          table.row(table.row_length - 1).font_style = :bold
          table.row(table.row_length - 1).background_color = "f6f8fa"
          table.columns(data.depth..(data.header.size - 1)).align = :right
          style_group_rows(table)
        end
      end

      # A parent row is a subtotal. Left looking like its children, a two-level
      # report reads as though every figure were counted twice.
      def style_group_rows(table)
        visible_rows.each_with_index do |row, index|
          next if row.leaf

          table.row(index + 1).font_style = :bold
        end
      end

      def visible_rows
        @visible_rows ||= data.rows.first(MAX_ROWS)
      end

      def table_rows
        [data.header] +
          visible_rows.map { |row| indent(row) + row.values.map { |value| cell(value) } } +
          [[data.footer_label] + Array.new(data.depth - 1, "") + data.footer_values.map { |value| cell(value) }]
      end

      # Indentation instead of repeating the parent on every line: a PDF is read
      # top to bottom and never sorted, so the nesting can carry the meaning
      # that the spreadsheet exports have to spell out.
      def indent(row)
        row.path.each_with_index.map do |value, index|
          next "" if value.nil?

          index == row.level ? value.to_s : ""
        end
      end

      def cell(value)
        return "" if value.to_f.zero?

        worklogs_measure(value, query.measure)
      end

      def table_options
        {
          header: true,
          width: pdf.bounds.width,
          cell_style: { size: TABLE_SIZE, padding: [3, 4, 3, 4], border_color: "d0d7de",
                        inline_format: false, overflow: :shrink_to_fit }
        }
      end

      def write_notes
        notes = data.notes
        notes << I18n.t("worklogs.reports.truncated_rows", count: data.rows.size - MAX_ROWS) if data.rows.size > MAX_ROWS
        return if notes.empty?

        pdf.move_down(8)
        pdf.font_size(META_SIZE) { notes.each { |note| pdf.text(note) } }
      end

      def write_footer
        pdf.number_pages("<page> / <total>",
                         at: [pdf.bounds.right - 60, -10],
                         size: META_SIZE,
                         align: :right)
      end

      def grouping_summary
        parts = query.row_dimensions.map(&:label)
        parts << I18n.t("worklogs.reports.by_column", dimension: query.column_dimension.label) if query.column_dimension

        parts.join(" › ")
      end

      def measure_label
        I18n.t("worklogs.reports.measures.#{query.measure}")
      end

      def filter_summary
        I18n.t("worklogs.reports.saved.filter_summary", count: query.filter_count)
      end
    end
  end
end
