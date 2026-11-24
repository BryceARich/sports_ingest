# frozen_string_literal: true

require "tempfile"
require "tmpdir"
require "yaml"
require "sports_ingest/nhl"

RSpec.describe SportsIngest::Identity::Crosswalk do
  def player(id, first, last, position, team, born, source_ids: {})
    SportsIngest::NHL::Player.new(
      ref: {sport: :hockey, canonical_id: id, source_ids: source_ids},
      first_name: first, last_name: last, position: position, team: team, birth_date: born,
      sweater_number: nil, shoots_catches: nil, height_inches: nil, weight_pounds: nil,
      birth_city: nil, birth_state_province: nil, birth_country: nil, headshot: nil
    )
  end

  let(:pettersson_c) { player(8480012, "Elias", "Pettersson", "C", "VAN", "1998-11-12") }
  let(:pettersson_d) { player(8483678, "Elias", "Pettersson", "D", "VAN", "2004-02-16") }
  let(:stutzle) { player(8482116, "Tim", "Stützle", "C", "OTT", "2002-01-15") }
  let(:players) { [pettersson_c, pettersson_d, stutzle] }
  let(:overrides) { SportsIngest::Identity::Overrides.new }
  let(:matcher) { SportsIngest::Identity::Matcher.new(players, overrides: overrides) }
  let(:store) { SportsIngest::Cache::MemoryStore.new }
  subject(:crosswalk) { described_class.new(matcher: matcher, store: store) }

  # An override sends the first Pettersson record to the other one, the way the file would.
  let(:matcher_with_override) do
    file = Tempfile.new(["overrides", ".yml"])
    file.write(YAML.dump([{"source" => "evolving_hockey", "source_id" => "ELIAS.PETTERSSON2", "canonical_id" => "8480012"}]))
    file.close
    SportsIngest::Identity::Matcher.new(players, overrides: SportsIngest::Identity::Overrides.load(file.path))
  end

  let(:records) do
    [
      {source: :evolving_hockey, id: "ELIAS.PETTERSSON2", name: "Elias Pettersson", position: "D", team: "VAN"},
      {source: :evolving_hockey, id: "TIM.STUTZLE", name: "Tim Stützle", birth_date: "2002-01-15"}
    ]
  end

  describe "#resolve" do
    it "matches through the matcher the first time and stores the link" do
      match = crosswalk.resolve(**records.first)

      expect([match.ref.canonical_id, match.reason]).to eq(["8483678", :name_position_team])
      expect(crosswalk.size).to eq(1)
    end

    it "does no fuzzy matching for a record it has already resolved" do
      crosswalk.resolve(**records.first)
      allow(matcher).to receive(:match).and_call_original

      again = crosswalk.resolve(**records.first)

      expect(matcher).not_to have_received(:match)
      expect([again.ref.canonical_id, again.reason]).to eq(["8483678", :name_position_team])
      expect(again.detail).to start_with("crosswalk: ")
    end

    it "stores nothing for an unmatched record, so it's retried when players are added" do
      ambiguous = {source: :x, name: "Elias Pettersson"}
      match = crosswalk.resolve(**ambiguous)

      expect([match.reason, match.matched?]).to eq([:ambiguous, false])
      expect(crosswalk.size).to eq(0)
    end

    it "applies an override even when a link was stored before the override existed" do
      crosswalk.resolve(**records.first)
      with_override = described_class.new(matcher: matcher_with_override, store: store)

      match = with_override.resolve(**records.first)

      expect([match.ref.canonical_id, match.reason]).to eq(["8480012", :override])
    end

    it "doesn't store an override, so editing the overrides file takes effect at once" do
      with_override = described_class.new(matcher: matcher_with_override, store: store)

      with_override.resolve(**records.first)

      expect(with_override.size).to eq(0)
    end
  end

  describe "#resolve_all and #save" do
    it "saves once, and a new crosswalk on the same file does no fuzzy matching" do
      Dir.mktmpdir do |dir|
        disk = SportsIngest::Cache::DiskStore.new(dir)
        first = described_class.new(matcher: matcher, store: disk)
        first.resolve_all(records)

        second_matcher = SportsIngest::Identity::Matcher.new(players, overrides: overrides)
        allow(second_matcher).to receive(:match).and_call_original
        second = described_class.new(matcher: second_matcher, store: disk)
        matches = second.resolve_all(records)

        expect(second_matcher).not_to have_received(:match)
        expect(matches.map(&:ref).map(&:canonical_id)).to eq(["8483678", "8482116"])
        expect(matches.map(&:reason)).to eq(%i[name_position_team name_and_birth_date])
      end
    end

    it "stores a PlayerRef that reads back equal to the one matched" do
      original = crosswalk.resolve(**records.first).ref
      crosswalk.save

      reloaded = described_class.new(matcher: matcher, store: store).resolve(**records.first)

      expect(reloaded.ref).to eq(original)
    end

    it "writes nothing when no link was added" do
      allow(store).to receive(:write)

      crosswalk.save

      expect(store).not_to have_received(:write)
    end

    it "ignores a file for another sport or format version" do
      store.write("hockey", {"format_version" => 99, "sport" => "hockey", "links" => {"x" => {}}})

      expect(described_class.new(matcher: matcher, store: store).size).to eq(0)
    end

    it "matches again when a stored link is damaged" do
      key = JSON.generate(["evolving_hockey", "ELIAS.PETTERSSON2", "Elias Pettersson", nil, "D", "VAN"])
      store.write("hockey", {"format_version" => 1, "sport" => "hockey",
                             "links" => {key => {"reason" => "name_position_team", "detail" => "d", "ref" => {"bad" => 1}}}})

      match = described_class.new(matcher: matcher, store: store).resolve(**records.first)

      expect([match.ref.canonical_id, match.reason]).to eq(["8483678", :name_position_team])
    end
  end

  describe "#clear" do
    it "forgets every link and deletes the file" do
      crosswalk.resolve_all(records)

      crosswalk.clear

      expect([crosswalk.size, store.read("hockey")]).to eq([0, nil])
    end
  end
end
