# frozen_string_literal: true

require "sports_ingest/espn"

RSpec.describe SportsIngest::ESPN::Filter do
  describe ".players" do
    it "spells each option the way ESPN does" do
      filter = described_class.players(limit: 50, offset: 100, ids: [1, 2], status: [:free_agent, :waivers],
        slot_ids: [0, 6], sort_percent_owned: true)

      expect(filter.to_h).to eq("players" => {
        "limit" => 50, "offset" => 100,
        "filterIds" => {"value" => [1, 2]},
        "filterStatus" => {"value" => %w[FREEAGENT WAIVERS]},
        "filterSlotIds" => {"value" => [0, 6]},
        "sortPercOwned" => {"sortPriority" => 1, "sortAsc" => false}
      })
    end

    it "leaves out what isn't given" do
      expect(described_class.players(status: :on_team).to_header)
        .to eq('{"players":{"filterStatus":{"value":["ONTEAM"]}}}')
    end

    it "rejects an unknown status" do
      expect { described_class.players(status: :injured) }.to raise_error(ArgumentError, /status must be one of/)
    end
  end

  describe "#merge" do
    it "deep-merges into a new filter, the argument winning" do
      base = described_class.players(limit: 50)
      merged = base.merge(players: {limit: 25, offset: 50})

      expect(merged.to_h).to eq("players" => {"limit" => 25, "offset" => 50})
      expect(base.to_h).to eq("players" => {"limit" => 50})
    end
  end

  it "is frozen through and leaves the caller's values alone" do
    name = +"x"
    filter = described_class.new(schedule: {names: [name]})

    expect(filter).to be_frozen
    expect(filter.to_h.dig("schedule", "names")).to be_frozen
    expect(name).not_to be_frozen
  end

  it "compares by content" do
    expect(described_class.new(a: 1)).to eq(described_class.new("a" => 1))
    expect(described_class.new(a: 1).hash).to eq(described_class.new("a" => 1).hash)
  end

  it "wraps a Hash and rejects anything else" do
    expect(described_class.wrap(a: 1)).to eq(described_class.new(a: 1))
    expect { described_class.wrap("{}") }.to raise_error(ArgumentError, /Filter or a Hash/)
  end
end
