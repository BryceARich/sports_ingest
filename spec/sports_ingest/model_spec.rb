# frozen_string_literal: true

RSpec.describe SportsIngest::Model do
  let(:team_class) { described_class.define(:abbrev, :name) }

  let(:player_class) do
    team_model = team_class
    described_class.define(:name, :team, :positions, :stats, schema_version: 3) do
      define_method(:initialize) do |team: nil, **fields|
        super(team: team_model.coerce(team), **fields)
      end
    end
  end

  let(:player) do
    player_class.new(
      name: "Connor McDavid",
      team: {abbrev: "EDM", name: "Edmonton Oilers"},
      positions: ["C"],
      stats: {"goals" => 32, "assists" => 68}
    )
  end

  describe ".define" do
    it "builds a Data class that is a Model and carries its schema version" do
      expect(player_class.ancestors).to include(Data, described_class)
      expect(player_class::SCHEMA_VERSION).to eq(3)
      expect(team_class::SCHEMA_VERSION).to eq(1)
    end

    it "rejects a schema version that isn't a positive Integer" do
      expect { described_class.define(:x, schema_version: 0) }.to raise_error(ArgumentError)
      expect { described_class.define(:x, schema_version: "1") }.to raise_error(ArgumentError)
    end
  end

  describe "immutability" do
    it "deep-freezes fields without freezing the caller's objects" do
      positions = ["C"]
      model = player_class.new(name: +"x", team: nil, positions: positions, stats: {})

      expect(model).to be_frozen
      expect(model.name).to be_frozen
      expect(model.positions).to be_frozen
      expect(model.stats).to be_frozen
      expect(positions).not_to be_frozen
      expect { model.positions << "LW" }.to raise_error(FrozenError)
    end

    it "keeps values frozen through #with" do
      expect(player.with(positions: ["LW"]).positions).to be_frozen
    end

    it "compares by value" do
      expect(player).to eq(player_class.from_h(player.to_h))
    end
  end

  describe "#to_h" do
    it "converts nested models to hashes" do
      expect(player.to_h).to eq(
        name: "Connor McDavid",
        team: {abbrev: "EDM", name: "Edmonton Oilers"},
        positions: ["C"],
        stats: {"goals" => 32, "assists" => 68}
      )
    end
  end

  describe "round trip" do
    it "survives to_h and from_h" do
      expect(player_class.from_h(player.to_h)).to eq(player)
    end

    it "survives to_json, JSON.parse and from_h" do
      restored = player_class.from_h(JSON.parse(player.to_json))

      expect(restored).to eq(player)
      expect(restored.team).to be_a(team_class)
    end
  end

  describe ".from_h" do
    it "raises on a missing field" do
      expect { team_class.from_h(abbrev: "EDM") }.to raise_error(ArgumentError, /name/)
    end

    it "raises on an unknown field" do
      expect { team_class.from_h(abbrev: "EDM", name: "x", city: "Edmonton") }
        .to raise_error(ArgumentError, /city/)
    end
  end

  describe ".coerce" do
    it "passes through an instance or nil and builds from a hash" do
      team = team_class.new(abbrev: "EDM", name: "Edmonton Oilers")

      expect(team_class.coerce(team)).to equal(team)
      expect(team_class.coerce(nil)).to be_nil
      expect(team_class.coerce("abbrev" => "EDM", "name" => "Edmonton Oilers")).to eq(team)
    end

    it "raises on anything else" do
      expect { team_class.coerce("EDM") }.to raise_error(ArgumentError, /String/)
    end
  end

  describe "shared field checks" do
    let(:checker) { SportsIngest::Model.define(:value) }

    it "check_integer enforces type, minimum and nil" do
      expect { checker.check_integer(:n, 3, min: 1) }.not_to raise_error
      expect { checker.check_integer(:n, nil, allow_nil: true) }.not_to raise_error
      expect { checker.check_integer(:n, 0, min: 1) }.to raise_error(ArgumentError, /n must be an Integer of at least 1, got 0/)
      expect { checker.check_integer(:n, nil) }.to raise_error(ArgumentError, /n must be an Integer, got nil/)
      expect { checker.check_integer(:n, "3") }.to raise_error(ArgumentError, /an Integer/)
    end

    it "check_boolean enforces true or false, with nil when allowed" do
      expect { checker.check_boolean(:flag, false) }.not_to raise_error
      expect { checker.check_boolean(:flag, nil, allow_nil: true) }.not_to raise_error
      expect { checker.check_boolean(:flag, nil) }.to raise_error(ArgumentError, /flag must be true or false/)
      expect { checker.check_boolean(:flag, "yes", allow_nil: true) }.to raise_error(ArgumentError, /true, false or nil/)
    end

    it "check_strings requires an Array of Strings" do
      expect(checker.check_strings(:words, ["PP"])).to eq(["PP"])
      expect { checker.check_strings(:words, "PP") }.to raise_error(ArgumentError, /Array of Strings/)
      expect { checker.check_strings(:words, ["PP", 1]) }.to raise_error(ArgumentError, /Array of Strings/)
    end

    it "coerce_codes allows listed keys, converts values and sorts by key" do
      codes = checker.coerce_codes({"b" => 2, :a => 1}, keys: %i[a b]) { |_key, value| value }

      expect(codes).to eq({a: 1, b: 2})
      expect(codes.keys).to eq(%i[a b])
    end

    it "coerce_codes rejects unknown keys by name, or by pattern" do
      expect { checker.coerce_codes({c: 1}, keys: %i[a b]) { |_, v| v } }
        .to raise_error(ArgumentError, /codes has no field :c/)
      expect { checker.coerce_codes({c: 1}, keys: /\A[a-z]+\z/, noun: "source") { |_, v| v } }
        .not_to raise_error
      expect { checker.coerce_codes({"Bad Key": 1}, keys: /\A[a-z]+\z/, noun: "source") { |_, v| v } }
        .to raise_error(ArgumentError, /codes has no source/)
    end

    it "coerce_codes requires a Hash" do
      expect { checker.coerce_codes([:a], keys: %i[a]) { |_, v| v } }.to raise_error(ArgumentError, /must be a Hash/)
    end
  end
end
