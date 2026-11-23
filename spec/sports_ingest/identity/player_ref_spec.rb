# frozen_string_literal: true

RSpec.describe SportsIngest::Identity::PlayerRef do
  let(:hockey) { described_class.new(sport: :hockey, canonical_id: 8_478_402, source_ids: {espn: 3_895_074}) }
  let(:football) { described_class.new(sport: "football", canonical_id: "00-0033873") }

  it "is a model with a schema version" do
    expect(described_class.ancestors).to include(SportsIngest::Model)
    expect(described_class::SCHEMA_VERSION).to eq(1)
  end

  describe ".new" do
    it "stores the sport as a Symbol and every ID as a String" do
      expect(hockey.sport).to eq(:hockey)
      expect(hockey.canonical_id).to eq("8478402")
      expect(hockey.source_ids).to eq(espn: "3895074", nhl: "8478402")
      expect(football.sport).to eq(:football)
    end

    it "fills in the canonical source's ID" do
      expect(hockey.source_id(:nhl)).to eq("8478402")
      expect(football.source_ids).to eq(nflverse: "00-0033873")
    end

    it "accepts the canonical source's ID when it matches" do
      ref = described_class.new(sport: :hockey, canonical_id: "8478402", source_ids: {"nhl" => 8_478_402})
      expect(ref).to eq(described_class.new(sport: :hockey, canonical_id: 8_478_402))
    end

    it "is deeply frozen" do
      expect(hockey).to be_frozen
      expect(hockey.source_ids).to be_frozen
      expect(hockey.canonical_id).to be_frozen
    end

    it "rejects an unknown sport" do
      expect { described_class.new(sport: :curling, canonical_id: "1") }
        .to raise_error(ArgumentError, /unknown sport :curling/)
    end

    it "rejects a canonical ID in the wrong format for the sport" do
      ["00-0033873", "0123", "84784O2"].each do |id|
        expect { described_class.new(sport: :hockey, canonical_id: id) }
          .to raise_error(ArgumentError, /valid hockey canonical ID/)
      end
      [8_478_402, "0-0033873", "00-00338730"].each do |id|
        expect { described_class.new(sport: :football, canonical_id: id) }
          .to raise_error(ArgumentError, /valid football canonical ID/)
      end
    end

    it "rejects blank and non-scalar IDs" do
      expect { described_class.new(sport: :hockey, canonical_id: " ") }.to raise_error(ArgumentError, /blank/)
      expect { described_class.new(sport: :hockey, canonical_id: nil) }.to raise_error(ArgumentError, /NilClass/)
      expect { described_class.new(sport: :hockey, canonical_id: "1", source_ids: {espn: ""}) }
        .to raise_error(ArgumentError, /blank/)
    end

    it "rejects source_ids that aren't a Hash or have bad source names" do
      expect { described_class.new(sport: :hockey, canonical_id: "1", source_ids: [[:espn, "1"]]) }
        .to raise_error(ArgumentError, /must be a Hash/)
      expect { described_class.new(sport: :hockey, canonical_id: "1", source_ids: {"ESPN" => "1"}) }
        .to raise_error(ArgumentError, /invalid source name/)
    end

    it "rejects a canonical source ID that disagrees with the canonical ID" do
      expect { described_class.new(sport: :hockey, canonical_id: "8478402", source_ids: {nhl: "8477934"}) }
        .to raise_error(ArgumentError, /source_ids\[:nhl\]/)
    end
  end

  describe "#canonical_source" do
    it "is the sport's authoritative source" do
      expect(hockey.canonical_source).to eq(:nhl)
      expect(football.canonical_source).to eq(:nflverse)
    end
  end

  describe "#source_id" do
    it "looks up by Symbol or String and returns nil when missing" do
      expect(hockey.source_id(:espn)).to eq("3895074")
      expect(hockey.source_id("espn")).to eq("3895074")
      expect(hockey.source_id(:puckpedia)).to be_nil
    end
  end

  describe "#with_source_id" do
    it "returns a new ref with the ID added, leaving the original alone" do
      updated = hockey.with_source_id("evolving_hockey", "CONNOR.MCDAVID")
      expect(updated.source_id(:evolving_hockey)).to eq("CONNOR.MCDAVID")
      expect(hockey.source_id(:evolving_hockey)).to be_nil
    end

    it "won't change the canonical source's ID" do
      expect { hockey.with_source_id(:nhl, "8477934") }.to raise_error(ArgumentError)
    end
  end

  describe "#key" do
    it "scopes the canonical ID by sport" do
      expect(hockey.key).to eq("hockey:8478402")
      expect(football.key).to eq("football:00-0033873")
    end
  end

  describe "serialization" do
    it "round-trips through JSON" do
      [hockey, football].each do |ref|
        expect(described_class.from_h(JSON.parse(ref.to_json))).to eq(ref)
      end
    end

    it "writes plain JSON values" do
      expect(JSON.parse(hockey.to_json)).to eq(
        "sport" => "hockey", "canonical_id" => "8478402",
        "source_ids" => {"espn" => "3895074", "nhl" => "8478402"}
      )
    end
  end
end
