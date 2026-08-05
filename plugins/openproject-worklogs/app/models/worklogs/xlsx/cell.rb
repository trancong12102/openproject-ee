module Worklogs
  module Xlsx
    # One cell, and the two decisions it makes: is this a number, and what does
    # it look like as XML.
    #
    # Numbers are written as numbers — that is the whole reason this workbook
    # exists rather than a CSV. Everything else goes out as an inline string,
    # which costs a few bytes over a shared string table and saves a whole part
    # of the format.
    class Cell
      # Characters XML 1.0 cannot carry at all. A time entry comment is free
      # text somebody pasted from somewhere, and one stray control character
      # would make the whole file unopenable rather than merely ugly.
      INVALID_XML = /[^\u{9}\u{A}\u{D}\u{20}-\u{D7FF}\u{E000}-\u{FFFD}\u{10000}-\u{10FFFF}]/

      attr_reader :value, :reference, :format, :bold

      def self.escape(text)
        text.to_s
            .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
            .gsub(INVALID_XML, "")
            .gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      end

      # Attribute values need one escape more than text does. A currency format
      # code carries the sign in double quotes — `#,##0.00 "€"` — so leaving
      # this out closes the attribute early and the file will not open at all.
      def self.escape_attribute(text)
        escape(text).gsub('"', "&quot;")
      end

      # A1, B1 … Z1, AA1. Excel will open a file with the wrong references, and
      # then quietly disagree with it about which column anything is in.
      def self.column_name(index)
        name = +""
        number = index + 1

        while number.positive?
          number, remainder = (number - 1).divmod(26)
          name.prepend((remainder + 65).chr)
        end

        name
      end

      def initialize(value:, reference:, format: nil, bold: false)
        @value = value
        @reference = reference
        @format = format
        @bold = bold
      end

      def blank?
        value.nil? || (value.respond_to?(:empty?) && value.empty?)
      end

      def number?
        value.is_a?(Numeric)
      end

      def to_xml
        return "" if blank?
        return %(<c r="#{reference}" s="#{style}"><v>#{number_value}</v></c>) if number?

        %(<c r="#{reference}" s="#{style}" t="inlineStr"><is><t xml:space="preserve">) +
          "#{self.class.escape(value)}</t></is></c>"
      end

      # Only a numeric cell carries a number format; a string in a column of
      # figures is a note, and formatting it as currency would be a lie.
      def style
        Styles.for(number? ? format : nil, bold:)
      end

      private

      def number_value
        return value.to_i if value.is_a?(Integer)

        rounded = value.to_f.round(6)
        rounded == rounded.to_i ? rounded.to_i : rounded
      end
    end
  end
end
