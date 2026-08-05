module Worklogs
  module Xlsx
    # A minimal .xlsx writer.
    #
    # There is no xlsx gem in this image's frozen bundle and none can be added
    # — no compiler, no git, and `bundle install` cannot re-resolve the Gemfile
    # at all. `spreadsheet` is there and writes the 1997 .xls format, which is
    # what `Reports::XlsExport` still uses.
    #
    # An .xlsx is a zip of XML parts, and rubyzip *is* in the bundle, so the
    # format is written out directly. This is deliberately the smallest thing
    # that opens correctly in Excel, LibreOffice and Numbers: inline strings
    # (no shared string table), one style table, no charts, no themes.
    #
    # What it does insist on: figures are written as numbers with a cell
    # format, never as text. A workbook whose totals cannot be re-summed is a
    # screenshot with extra steps.
    class Workbook
      SPREADSHEET_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main".freeze
      RELATIONSHIP_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships".freeze
      PACKAGE_NS = "http://schemas.openxmlformats.org/package/2006/relationships".freeze
      CONTENT_TYPES_NS = "http://schemas.openxmlformats.org/package/2006/content-types".freeze

      CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze

      attr_reader :sheets

      def initialize
        @sheets = []
        yield self if block_given?
      end

      def sheet(name)
        Sheet.new(name).tap do |sheet|
          @sheets << sheet
          yield sheet if block_given?
        end
      end

      def to_xlsx
        require "zip"

        buffer = Zip::OutputStream.write_buffer(StringIO.new) do |zip|
          parts.each do |path, content|
            zip.put_next_entry(path)
            zip.write(content)
          end
        end

        buffer.string
      end

      private

      def parts
        parts = { "[Content_Types].xml" => content_types,
                  "_rels/.rels" => root_relationships,
                  "xl/workbook.xml" => workbook_part,
                  "xl/_rels/workbook.xml.rels" => workbook_relationships,
                  "xl/styles.xml" => Styles.to_xml }

        sheets.each_with_index do |sheet, index|
          parts["xl/worksheets/sheet#{index + 1}.xml"] = sheet.to_xml
        end

        parts
      end

      def content_types
        overrides = sheets.each_index.map do |index|
          %(<Override PartName="/xl/worksheets/sheet#{index + 1}.xml" ) +
            %(ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>)
        end

        <<~XML
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
          <Types xmlns="#{CONTENT_TYPES_NS}">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
          #{overrides.join}
          </Types>
        XML
      end

      def root_relationships
        <<~XML
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
          <Relationships xmlns="#{PACKAGE_NS}">
          <Relationship Id="rId1" Type="#{RELATIONSHIP_NS}/officeDocument" Target="xl/workbook.xml"/>
          </Relationships>
        XML
      end

      def workbook_part
        entries = sheets.each_with_index.map do |sheet, index|
          %(<sheet name="#{Cell.escape_attribute(sheet.name)}" sheetId="#{index + 1}" r:id="rId#{index + 1}"/>)
        end

        <<~XML
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
          <workbook xmlns="#{SPREADSHEET_NS}" xmlns:r="#{RELATIONSHIP_NS}">
          <sheets>#{entries.join}</sheets>
          </workbook>
        XML
      end

      def workbook_relationships
        entries = sheets.each_index.map do |index|
          %(<Relationship Id="rId#{index + 1}" Type="#{RELATIONSHIP_NS}/worksheet" ) +
            %(Target="worksheets/sheet#{index + 1}.xml"/>)
        end
        entries << %(<Relationship Id="rId#{sheets.size + 1}" Type="#{RELATIONSHIP_NS}/styles" Target="styles.xml"/>)

        <<~XML
          <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
          <Relationships xmlns="#{PACKAGE_NS}">
          #{entries.join}
          </Relationships>
        XML
      end
    end
  end
end
