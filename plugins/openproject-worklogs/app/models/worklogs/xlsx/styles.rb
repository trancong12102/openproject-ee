module Worklogs
  module Xlsx
    # The one style table every sheet in the workbook shares.
    #
    # Small on purpose: a plain cell, a bold one, and each number format in
    # both weights. A style is an index into `cellXfs`, so these constants are
    # what `Sheet` writes into `s="…"`.
    #
    # Excel is unforgiving about this part of the format — `fills` must have at
    # least the two entries below even though nothing uses the second, the
    # named "Normal" style has to be declared even though nothing refers to it,
    # and the order of the elements inside `styleSheet` is fixed by the schema.
    module Styles
      # Built-in number formats: 1 is "0", 2 is "0.00". Anything else has to be
      # declared, and 164 is the first id an application is allowed to use.
      CURRENCY_FORMAT_ID = 164

      DEFAULT = 0
      BOLD = 1
      DECIMAL = 2
      INTEGER = 3
      CURRENCY = 4
      BOLD_DECIMAL = 5
      BOLD_INTEGER = 6
      BOLD_CURRENCY = 7

      # What a column of figures is: hours (2 decimals), a count, or money.
      FORMATS = { hours: DECIMAL, integer: INTEGER, currency: CURRENCY }.freeze
      BOLD_FORMATS = { hours: BOLD_DECIMAL, integer: BOLD_INTEGER, currency: BOLD_CURRENCY }.freeze

      class << self
        def for(format, bold: false)
          return bold ? BOLD : DEFAULT if format.nil?

          (bold ? BOLD_FORMATS : FORMATS).fetch(format, bold ? BOLD : DEFAULT)
        end

        def to_xml
          <<~XML
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <styleSheet xmlns="#{Workbook::SPREADSHEET_NS}">
            <numFmts count="1"><numFmt numFmtId="#{CURRENCY_FORMAT_ID}" formatCode="#{Cell.escape_attribute(currency_format)}"/></numFmts>
            <fonts count="2">
            <font><sz val="11"/><name val="Calibri"/></font>
            <font><b/><sz val="11"/><name val="Calibri"/></font>
            </fonts>
            <fills count="2">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
            </fills>
            <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
            <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
            <cellXfs count="8">
            #{cell_formats.join("\n")}
            </cellXfs>
            <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
            </styleSheet>
          XML
        end

        # The instance's own currency sign, so the workbook reads the way the
        # screen did rather than in whatever locale Excel happens to open in.
        def currency_format
          sign = Setting.costs_currency.to_s.delete('"')
          pattern = Setting.costs_currency_format.to_s.presence || "%n %u"

          pattern.gsub("%n", "#,##0.00").gsub("%u", %("#{sign}"))
        rescue StandardError
          "#,##0.00"
        end

        private

        # Order matters: the index of each line here is the style id above.
        def cell_formats
          [xf(0, bold: false), xf(0, bold: true),
           xf(2, bold: false), xf(1, bold: false), xf(CURRENCY_FORMAT_ID, bold: false),
           xf(2, bold: true), xf(1, bold: true), xf(CURRENCY_FORMAT_ID, bold: true)]
        end

        def xf(number_format_id, bold:)
          %(<xf numFmtId="#{number_format_id}" fontId="#{bold ? 1 : 0}" fillId="0" borderId="0" xfId="0" ) +
            %(applyNumberFormat="1" applyFont="1"/>)
        end
      end
    end
  end
end
