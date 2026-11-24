# frozen_string_literal: true

require "sports_ingest/espn"

RSpec.describe SportsIngest::ESPN::StatIds do
  it "has a dictionary per sport, under either name" do
    expect(described_class.for(:football)).to equal(described_class::FOOTBALL)
    expect(described_class.for("ffl")).to equal(described_class::FOOTBALL)
    expect(described_class.for(:hockey)).to equal(described_class::HOCKEY)
  end

  it "looks up abbreviations and descriptions, with Integer or String IDs" do
    expect(described_class.abbrev(:football, 53)).to eq("REC")
    expect(described_class.abbrev(:football, "3")).to eq("PY")
    expect(described_class.description(:hockey, 38)).to eq("Power-play points")
  end

  it "returns nil for unknown IDs" do
    expect(described_class.abbrev(:hockey, 999)).to be_nil
    expect(described_class.description(:football, "x")).to be_nil
  end

  it "rejects an unknown game" do
    expect { described_class.for(:curling) }.to raise_error(ArgumentError, /game must be one of/)
  end

  it "has an abbreviation and a description for every entry" do
    [described_class::FOOTBALL, described_class::HOCKEY].each do |table|
      expect(table.keys).to all(be_an(Integer))
      expect(table.values).to all(match(abbrev: a_kind_of(String), name: a_kind_of(String)))
      expect(table.values.map { |stat| stat[:abbrev] }).to eq(table.values.map { |stat| stat[:abbrev] }.uniq)
    end
  end
end
