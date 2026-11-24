# frozen_string_literal: true

require "tempfile"

RSpec.describe SportsIngest::Identity::Overrides do
  describe ".new" do
    it "finds an override by source ID, with a string or integer ID" do
      overrides = described_class.new([{source: "espn", source_id: 3900169, canonical_id: "8478427"}])

      expect(overrides.find(source: :espn, name: "Anyone", id: "3900169")).to eq(["8478427", 'espn ID "3900169"'])
    end

    it "finds an override by source name, whatever the spelling" do
      overrides = described_class.new([{"source" => "puckpedia", "source_name" => "Tim Stützle", "canonical_id" => 8482116}])

      expect(overrides.find(source: :puckpedia, name: "STUTZLE, TIM")).to eq(["8482116", 'puckpedia name "tim stutzle"'])
    end

    it "prefers an ID override over a name override" do
      overrides = described_class.new([
        {source: "x", source_name: "Tim Stutzle", canonical_id: "8482116"},
        {source: "x", source_id: "A1", canonical_id: "8480012"}
      ])

      expect(overrides.find(source: :x, name: "Tim Stutzle", id: "A1").first).to eq("8480012")
      expect(overrides.find(source: :x, name: "Tim Stutzle", id: "B2").first).to eq("8482116")
    end

    it "matches nothing for another source or an unknown ID" do
      overrides = described_class.new([{source: "x", source_id: "A1", canonical_id: "8480012"}])

      expect(overrides.find(source: :y, name: "Anyone", id: "A1")).to be_nil
      expect(overrides.find(source: :x, name: "Anyone", id: "B2")).to be_nil
    end

    it "lists the canonical IDs it points at, without duplicates" do
      overrides = described_class.new([
        {source: "x", source_id: "A1", canonical_id: "8480012"},
        {source: "x", source_name: "Elias Pettersson", canonical_id: "8480012"}
      ])

      expect(overrides.canonical_ids).to eq(["8480012"])
    end

    it "refuses an entry it can't read" do
      expect { described_class.new(["not a mapping"]) }.to raise_error(ArgumentError, /mapping/)
      expect { described_class.new([{source: "x", canonical_id: "1"}]) }.to raise_error(ArgumentError, /exactly one of/)
      expect { described_class.new([{source: "x", source_id: "A", source_name: "B", canonical_id: "1"}]) }
        .to raise_error(ArgumentError, /exactly one of/)
      expect { described_class.new([{source_id: "A", canonical_id: "1"}]) }.to raise_error(ArgumentError, /needs a source/)
      expect { described_class.new([{source: "x", source_id: "A"}]) }.to raise_error(ArgumentError, /canonical_id/)
      expect { described_class.new([{source: "x", source_id: "A", canonical_id: "1", nhl: "1"}]) }
        .to raise_error(ArgumentError, /unknown override keys: nhl/)
      expect { described_class.new([{source: "Bad Source", source_id: "A", canonical_id: "1"}]) }
        .to raise_error(ArgumentError, /snake_case/)
    end

    it "refuses two entries that give one key different players" do
      entries = [
        {source: "x", source_id: "A1", canonical_id: "8480012"},
        {source: "x", source_id: "A1", canonical_id: "8483678"}
      ]

      expect { described_class.new(entries) }.to raise_error(ArgumentError, /conflicting overrides/)
    end

    it "accepts the same entry twice" do
      entry = {source: "x", source_id: "A1", canonical_id: "8480012"}

      expect(described_class.new([entry, entry]).canonical_ids).to eq(["8480012"])
    end
  end

  describe ".load" do
    def with_file(text)
      Tempfile.create(["overrides", ".yml"]) do |file|
        file.write(text)
        file.flush
        yield file.path
      end
    end

    it "reads a YAML list of entries" do
      with_file(<<~YAML) do |path|
        - source: evolving_hockey
          source_id: ELIAS.PETTERSSON2
          canonical_id: 8483678
      YAML
        expect(described_class.load(path).find(source: :evolving_hockey, name: "x", id: "ELIAS.PETTERSSON2").first)
          .to eq("8483678")
      end
    end

    it "reads an empty file as no overrides" do
      with_file("") { |path| expect(described_class.load(path).canonical_ids).to eq([]) }
    end

    it "raises ConfigurationError for a missing file" do
      expect { described_class.load("/no/such/overrides.yml") }
        .to raise_error(SportsIngest::ConfigurationError, %r{no overrides file})
    end

    it "raises ParseError for YAML that isn't a list of entries" do
      with_file("source: x\n") do |path|
        expect { described_class.load(path) }.to raise_error(SportsIngest::ParseError, /list of overrides/)
      end
      with_file("- [unclosed\n") do |path|
        expect { described_class.load(path) }.to raise_error(SportsIngest::ParseError, /isn't valid YAML/)
      end
    end
  end
end
