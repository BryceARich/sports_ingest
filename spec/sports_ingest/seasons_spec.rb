# frozen_string_literal: true

RSpec.describe SportsIngest::Seasons do
  it "counts last: N back from the current season, current included" do
    expect(described_class.resolve(last: 3, current: 2026)).to eq([2024, 2025, 2026])
    expect(described_class.resolve(last: 1, current: 2026)).to eq([2026])
  end

  it "sorts and de-duplicates an explicit list" do
    expect(described_class.resolve(seasons: [2025, 2019, 2025], current: 2026)).to eq([2019, 2025])
  end

  it "falls back to default_last when neither keyword is given" do
    expect(described_class.resolve(current: 2026, default_last: 2)).to eq([2025, 2026])
  end

  it "rejects both keywords, neither without a default, and bad values" do
    expect { described_class.resolve(seasons: [2025], last: 3, current: 2026) }.to raise_error(ArgumentError, /not both/)
    expect { described_class.resolve(current: 2026) }.to raise_error(ArgumentError, /seasons: .* or last:/)
    [0, -1, 2.0, "3"].each do |last|
      expect { described_class.resolve(last: last, current: 2026) }.to raise_error(ArgumentError, /positive Integer/)
    end
    [[], 2025, ["2025"], 2024..2025].each do |seasons|
      expect { described_class.resolve(seasons: seasons, current: 2026) }.to raise_error(ArgumentError, /non-empty Array/)
    end
    expect { described_class.resolve(last: 3, current: "2026") }.to raise_error(ArgumentError, /current/)
  end
end
