# frozen_string_literal: true

require_relative "../../rakelib/lib/doc_coverage"

RSpec.describe RepoTools::DocCoverage do
  def stats(percent)
    <<~OUT
      Files:          19
      Methods:        31 (    3 undocumented)
       #{percent}% documented

      Undocumented Objects:
      SportsIngest::Foo#bar   (lib/sports_ingest/foo.rb:3)
    OUT
  end

  it "reads the documented share from the summary line" do
    expect(described_class.new(stats("92.31")).percent).to eq(92.31)
  end

  it "passes at or above the threshold" do
    expect(described_class.new(stats("90.00"))).to be_passing
    expect(described_class.new(stats("100.00")).summary).to eq("yard: 100.00% documented, OK")
  end

  it "fails below the threshold" do
    coverage = described_class.new(stats("89.99"))

    expect(coverage).not_to be_passing
    expect(coverage.summary).to eq("yard: 89.99% documented, below the 90.00% threshold")
  end

  it "takes a threshold from the caller" do
    expect(described_class.new(stats("95.00"), threshold: "96")).not_to be_passing
  end

  it "raises when the output has no summary line" do
    expect { described_class.new("Error: no files").percent }
      .to raise_error(RepoTools::Error, /% documented/)
  end
end
