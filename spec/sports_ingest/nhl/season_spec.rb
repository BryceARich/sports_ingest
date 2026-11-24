# frozen_string_literal: true

require "sports_ingest/nhl"

RSpec.describe SportsIngest::NHL::Season do
  it "turns a start year into the NHL's season ID and back" do
    expect(described_class.id(2025)).to eq("20252026")
    expect(described_class.year("20252026")).to eq(2025)
    expect(described_class.year(19171918)).to eq(1917)
  end

  it "rejects years that aren't Integers in range" do
    [1916, "2025", 2025.0, nil].each do |year|
      expect { described_class.id(year) }.to raise_error(ArgumentError, /start year/)
    end
  end

  it "rejects IDs that aren't two consecutive years" do
    %w[20252027 2025 2025-26].each do |id|
      expect { described_class.year(id) }.to raise_error(ArgumentError, /NHL season ID/)
    end
  end

  it "rolls the current season over in October, keeping last season through the summer" do
    expect(described_class.current(Date.new(2026, 11, 23))).to eq(2026)
    expect(described_class.current(Date.new(2026, 10, 1))).to eq(2026)
    expect(described_class.current(Date.new(2026, 9, 30))).to eq(2025)
    expect(described_class.current(Date.new(2027, 4, 15))).to eq(2026)
    expect { described_class.current("2026-11-23") }.to raise_error(ArgumentError, /Date/)
  end
end
