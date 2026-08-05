module Worklogs
  module Xlsx
    # One worksheet, built a row at a time.
    #
    # The API is the shape every export in this plugin already has: a title
    # saying what was asked, the question's parameters, a header, the rows, a
    # totals line and any notes about what was left out.
    class Sheet
      MIN_WIDTH = 9
      MAX_WIDTH = 60
      # Roughly a character, plus room for the padding Excel adds.
      WIDTH_PADDING = 2

      attr_reader :name, :rows

      def initialize(name)
        # Excel refuses a sheet name over 31 characters or containing any of
        # []:*?/\ — and refuses to open the whole file rather than saying so.
        @name = name.to_s.gsub(%r{[\[\]:*?/\\]}, " ").strip.first(31).presence || "Sheet"
        @rows = []
        @formats = []
        @freeze_at = nil
      end

      # Which columns hold figures. `to:` left out means "and everything after
      # it", which is what a table of days or of pivot values actually is —
      # the width of those is a property of the data, not of this call.
      def format_columns(format, from:, to: nil)
        @formats << [(from..to), format]
        self
      end

      def format_column(index, format)
        format_columns(format, from: index, to: index)
      end

      # Later declarations win, so a total column can be given its own format
      # after the sweep that covered it.
      def format_for(index)
        @formats.reverse_each do |range, format|
          return format if range.cover?(index)
        end

        nil
      end

      def title(text)
        row([text], bold: true)
      end

      def blank
        row([])
      end

      def row(values, bold: false)
        @rows << { values: Array(values), bold: }
        self
      end

      # The header freezes itself in place: a hundred rows of hours with the
      # column titles scrolled off the top is unreadable, and everybody who
      # opens this file scrolls.
      def header(values)
        row(values, bold: true)
        @freeze_at = @rows.size
        self
      end

      def total(values)
        row(values, bold: true)
      end

      def note(text)
        row([text])
      end

      def to_xml
        <<~XML
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
          <worksheet xmlns="#{Workbook::SPREADSHEET_NS}">
          #{sheet_views}#{columns}<sheetData>#{sheet_data}</sheetData>
          </worksheet>
        XML
      end

      private

      def sheet_views
        return "" if @freeze_at.nil?

        %(<sheetViews><sheetView workbookViewId="0">) +
          %(<pane ySplit="#{@freeze_at}" topLeftCell="A#{@freeze_at + 1}" activePane="bottomLeft" state="frozen"/>) +
          "</sheetView></sheetViews>"
      end

      # Widths from the content, because a column of names all reading "####"
      # or cut off at eight characters is the first thing anybody notices.
      def columns
        return "" if widths.empty?

        entries = widths.map do |index, width|
          %(<col min="#{index + 1}" max="#{index + 1}" width="#{width}" customWidth="1"/>)
        end

        "<cols>#{entries.join}</cols>"
      end

      # Measured from the header down. What sits above it is preamble — the
      # title, and "Group by: Project › User" against a label — and none of it
      # says anything about how wide a column of hours wants to be.
      def widths
        @computed_widths ||= table_rows.each_with_object({}) do |line, widths|
          # A note is one long sentence in the first column. It is not what
          # column A is for, so it does not get to set its width either.
          next if line[:values].size <= 1

          line[:values].each_with_index do |value, index|
            length = display_length(value)
            widths[index] = [[widths[index] || MIN_WIDTH, length + WIDTH_PADDING].max, MAX_WIDTH].min
          end
        end
      end

      def table_rows
        @freeze_at ? @rows.drop(@freeze_at - 1) : @rows
      end

      def display_length(value)
        return 0 if value.nil?
        return 8 if value.is_a?(Numeric)

        [value.to_s.length, MAX_WIDTH].min
      end

      def sheet_data
        @rows.each_with_index.map { |line, index| row_xml(line, index + 1) }.join
      end

      def row_xml(line, number)
        cells = line[:values].each_with_index.map do |value, index|
          Cell.new(value:,
                   reference: "#{Cell.column_name(index)}#{number}",
                   format: format_for(index),
                   bold: line[:bold]).to_xml
        end

        %(<row r="#{number}">#{cells.join}</row>)
      end
    end
  end
end
