require "spec_helper"
require "zip"

RSpec.describe Worklogs::Xlsx::Workbook do
  subject(:parts) { unzip(workbook.to_xlsx) }

  let(:workbook) do
    described_class.new do |book|
      book.sheet("Hours") do |sheet|
        sheet.format_columns(:hours, from: 1)
        sheet.title("Team · August")
        sheet.header(%w[Who Hours])
        sheet.row(["Ann & <Bob>", 7.5])
        sheet.total(["Total", 7.5])
        sheet.note("Owed counts only days that have already happened.")
      end
    end
  end

  def unzip(data)
    entries = nil
    Zip::File.open_buffer(data) do |zip|
      entries = zip.entries.to_h { |entry| [entry.name, zip.read(entry.name)] }
    end
    entries
  end

  def sheet_xml = Nokogiri::XML(parts["xl/worksheets/sheet1.xml"])

  it "writes every part a reader opens" do
    expect(parts.keys).to include("[Content_Types].xml", "_rels/.rels", "xl/workbook.xml",
                                  "xl/_rels/workbook.xml.rels", "xl/styles.xml",
                                  "xl/worksheets/sheet1.xml")
  end

  it "writes well-formed XML in every part" do
    parts.each_value do |content|
      expect(Nokogiri::XML(content, &:strict).errors).to be_empty
    end
  end

  # The whole reason this exists rather than a CSV: a figure Excel will re-sum.
  it "writes figures as numbers and words as text" do
    hours = sheet_xml.at_css(%(c[r="B3"]))
    who = sheet_xml.at_css(%(c[r="A3"]))

    expect(hours.at_css("v").text).to eq("7.5")
    expect(hours["t"]).to be_nil
    expect(who["t"]).to eq("inlineStr")
    expect(who.at_css("t").text).to eq("Ann & <Bob>")
  end

  it "gives a number the format of its column and leaves text alone" do
    styles = sheet_xml.css("c").to_h { |cell| [cell["r"], cell["s"].to_i] }

    expect(styles["B3"]).to eq(Worklogs::Xlsx::Styles::DECIMAL)
    expect(styles["B4"]).to eq(Worklogs::Xlsx::Styles::BOLD_DECIMAL)
    expect(styles["A3"]).to eq(Worklogs::Xlsx::Styles::DEFAULT)
  end

  # A hundred rows of hours with the column titles scrolled off the top is
  # unreadable, and everybody who opens one of these scrolls.
  it "freezes the header row" do
    pane = sheet_xml.at_css("pane")

    expect(pane["state"]).to eq("frozen")
    expect(pane["ySplit"]).to eq("2")
  end

  # Measured from the header down: the title and the notes are sentences, and a
  # column of hours is not as wide as a sentence.
  it "sizes columns from the table, not from its title" do
    widths = sheet_xml.css("col").map { |col| col["width"].to_f }

    expect(widths).to all(be < Worklogs::Xlsx::Sheet::MAX_WIDTH)
  end

  describe "sheet names" do
    it "makes a name Excel would refuse safe rather than emitting a file it will not open" do
      sheet = Worklogs::Xlsx::Sheet.new("Report: 2026/08 [draft] and a very long tail indeed")

      expect(sheet.name.length).to be <= 31
      expect(sheet.name).not_to match(%r{[\[\]:*?/\\]})
    end

    it "never ends up with an empty name" do
      expect(Worklogs::Xlsx::Sheet.new("").name).to eq("Sheet")
    end
  end

  describe Worklogs::Xlsx::Cell do
    it "keeps counting columns past Z" do
      expect([0, 25, 26, 27, 51, 52].map { |i| described_class.column_name(i) })
        .to eq(%w[A Z AA AB AZ BA])
    end

    # A comment is free text somebody pasted from somewhere, and one stray
    # control character would make the file unopenable rather than merely ugly.
    it "drops characters XML cannot carry" do
      cell = described_class.new(value: "one\u0000two\u0008three", reference: "A1")

      expect(cell.to_xml).to include("onetwothree")
    end

    # The currency sign arrives inside double quotes; an unescaped one would
    # close the attribute early and take the whole file with it.
    it "escapes quotes in an attribute" do
      escaped = described_class.escape_attribute(%(#,##0.00 "€"))

      expect(escaped).not_to include('"')
      expect(Nokogiri::XML(%(<a b="#{escaped}"/>), &:strict).errors).to be_empty
    end

    it "writes nothing at all for a blank" do
      expect(described_class.new(value: nil, reference: "A1").to_xml).to eq("")
    end
  end
end
