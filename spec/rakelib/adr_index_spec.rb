# frozen_string_literal: true

require "tmpdir"
require_relative "../../rakelib/lib/adr_index"

RSpec.describe RepoTools::AdrIndex do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:index) { described_class.new(@dir) }
  let(:readme_path) { File.join(@dir, "README.md") }
  let(:row1) { "| [0001](0001-one.md) | Do one | Accepted |" }
  let(:row8) { "| [0008](0008-eight.md) | Do eight | Proposed |" }
  let(:row8b) { "| [0008](0008-http-client.md) | Add a client | Proposed |" }

  def adr(name, title, status)
    File.write(File.join(@dir, name), "# #{name[0, 4]}. #{title}\n\n- **Status:** #{status}\n- **Date:** 2026-11-22\n")
  end

  def readme(*rows)
    File.write(readme_path, ["# ADRs", "", "## Index", "", "| # | Decision | Status |", "|---|---|---|", *rows, "", "Footer."].join("\n") + "\n")
  end

  before do
    adr("0000-template.md", "Title", "Proposed | Accepted")
    adr("0001-one.md", "Do one", "Accepted")
    adr("0008-eight.md", "Do eight", "Proposed")
  end

  describe "#write!" do
    it "rewrites only the table, sorting by number then file name, skipping the template" do
      adr("0008-http-client.md", "Add a client", "Proposed")
      readme(row8)

      expect(index.write!).to be(true)
      expect(File.read(readme_path)).to include("|---|---|---|\n#{row1}\n#{row8}\n#{row8b}\n\nFooter.\n")
      expect(index.write!).to be(false)
    end

    it "raises when README.md has no table" do
      File.write(readme_path, "# ADRs\n")
      expect { index.write! }.to raise_error(RepoTools::Error, /no index table/)
    end
  end

  describe "#problems" do
    it "is empty for a correct table" do
      readme(row1, row8)
      expect(index.problems).to eq([])
    end

    it "allows ADRs that have no row yet and lists them as unindexed" do
      adr("0072-new.md", "Do new", "Proposed")
      readme(row1, row8)
      expect(index.problems).to eq([])
      expect(index.unindexed.map(&:file)).to eq(["0072-new.md"])
    end

    it "reports a row whose title or status is out of date" do
      readme(row1, row8.sub("Proposed", "Accepted"))
      expect(index.problems.join).to include("row for 0008-eight.md is out of date")
    end

    it "reports a row pointing at a missing file" do
      readme(row1, row8, "| [0009](0009-gone.md) | Gone | Accepted |")
      expect(index.problems.join).to include("row points at no ADR file")
    end

    it "reports rows out of order" do
      readme(row8, row1)
      expect(index.problems.join).to include("out of order")
    end
  end

  it "raises when an ADR's heading doesn't match its file number" do
    File.write(File.join(@dir, "0009-bad.md"), "# 0007. Wrong\n\n- **Status:** Proposed\n")
    expect { index.entries }.to raise_error(RepoTools::Error, /0009-bad\.md: first line/)
  end

  it "accepts this repo's ADR index" do
    repo = described_class.new(File.expand_path("../../docs/adr", __dir__))
    expect(repo.problems).to eq([])
  end
end
