# frozen_string_literal: true

require "sports_ingest/nhl"

RSpec.describe SportsIngest::Identity::Matcher do
  def player(id, first, last, position, team, born, source_ids: {})
    SportsIngest::NHL::Player.new(
      ref: {sport: :hockey, canonical_id: id, source_ids: source_ids},
      first_name: first, last_name: last, position: position, team: team, birth_date: born,
      sweater_number: nil, shoots_catches: nil, height_inches: nil, weight_pounds: nil,
      birth_city: nil, birth_state_province: nil, birth_country: nil, headshot: nil
    )
  end

  # Real NHL players; the two Petterssons are on the same team, so position has to tell them apart.
  let(:pettersson_c) { player(8480012, "Elias", "Pettersson", "C", "VAN", "1998-11-12") }
  let(:pettersson_d) { player(8483678, "Elias", "Pettersson", "D", "VAN", "2004-02-16") }
  let(:aho_car) { player(8478427, "Sebastian", "Aho", "C", "CAR", "1997-07-26", source_ids: {espn: 3900169}) }
  let(:aho_nyi) { player(8480222, "Sebastian", "Aho", "D", "NYI", "1996-02-17") }
  let(:stutzle) { player(8482116, "Tim", "Stützle", "C", "OTT", "2002-01-15") }
  let(:matcher) { described_class.new([pettersson_c, pettersson_d, aho_car, aho_nyi, stutzle]) }

  describe "acceptance: players who share a name" do
    it "tells the two Elias Petterssons apart by birth date" do
      expect(matcher.match(source: :evolving_hockey, name: "Elias Pettersson", birth_date: "1998-11-12").ref.canonical_id)
        .to eq("8480012")
      expect(matcher.match(source: :evolving_hockey, name: "PETTERSSON, ELIAS", birth_date: "2004-02-16").ref.canonical_id)
        .to eq("8483678")
    end

    it "tells the two Elias Petterssons apart by position on the same team" do
      center = matcher.match(source: :evolving_hockey, name: "Elias Pettersson", position: "C", team: "VAN")
      defense = matcher.match(source: :evolving_hockey, name: "Elias Pettersson", position: "D", team: "VAN")

      expect([center.ref.canonical_id, center.reason]).to eq(["8480012", :name_position_team])
      expect([defense.ref.canonical_id, defense.confidence]).to eq(["8483678", :medium])
    end

    it "tells the two Sebastian Ahos apart by birth date, team or position" do
      expect(matcher.match(source: :x, name: "Sebastian Aho", birth_date: Date.new(1997, 7, 26)).ref.canonical_id).to eq("8478427")
      expect(matcher.match(source: :x, name: "Sebastian Aho", position: "D", team: "NYI").ref.canonical_id).to eq("8480222")
      expect(matcher.match(source: :x, name: "Sebastian Aho", position: "F", team: "CAR").ref.canonical_id).to eq("8478427")
    end
  end

  describe "tier 1: source ID" do
    it "matches an ID already on a known player, whatever the name says" do
      match = matcher.match(source: :espn, id: 3900169, name: "Someone Else")

      expect([match.ref.canonical_id, match.confidence, match.reason]).to eq(["8478427", :exact, :source_id])
    end

    it "matches the canonical source's own ID" do
      expect(matcher.match(source: :nhl, id: "8482116", name: "Tim Stutzle").reason).to eq(:source_id)
    end

    it "doesn't name-match an unknown canonical ID, which would give the player a second NHL ID" do
      match = matcher.match(source: :nhl, id: 9999999, name: "Tim Stützle")

      expect([match.matched?, match.reason, match.candidates.map(&:canonical_id)]).to eq([false, :no_match, ["8482116"]])
    end
  end

  describe "tiers 2 to 4" do
    it "adds the source's ID to the matched ref" do
      match = matcher.match(source: :evolving_hockey, id: "TIM.STUTZLE", name: "Stützle, Tim")

      expect(match.ref.source_id(:evolving_hockey)).to eq("TIM.STUTZLE")
      expect(match.ref.canonical_id).to eq("8482116")
    end

    it "matches a unique name with low confidence" do
      match = matcher.match(source: :x, name: "TIM STUTZLE")

      expect([match.confidence, match.reason, match.candidates]).to eq([:low, :unique_name, []])
    end

    it "accepts any source's team code and position spelling" do
      match = matcher.match(source: :x, name: "Sebastian Aho", position: "RW", team: "Carolina Hurricanes")

      expect(match.ref.canonical_id).to eq("8478427")
    end

    it "sets aside players whose position group contradicts the record" do
      match = matcher.match(source: :x, name: "Elias Pettersson", position: "LD")

      expect([match.ref.canonical_id, match.reason]).to eq(["8483678", :unique_name])
    end

    it "falls back to the name when the team doesn't match (a trade)" do
      match = matcher.match(source: :x, name: "Sebastian Aho", position: "D", team: "PIT")

      expect([match.ref.canonical_id, match.reason]).to eq(["8480222", :unique_name])
    end

    it "rejects a unique name whose birth date contradicts the record" do
      match = matcher.match(source: :x, name: "Tim Stützle", birth_date: "1990-01-01")

      expect([match.matched?, match.reason, match.candidates.size]).to eq([false, :no_match, 1])
    end

    it "reports a shared name it can't split as ambiguous, with the candidates" do
      match = matcher.match(source: :x, name: "Elias Pettersson")

      expect([match.matched?, match.confidence, match.reason]).to eq([false, :none, :ambiguous])
      expect(match.candidates.map(&:canonical_id)).to contain_exactly("8480012", "8483678")
    end

    it "reports an unknown name as no_match" do
      match = matcher.match(source: :x, name: "Wayne Gretzky")

      expect([match.reason, match.candidates, match.detail]).to eq([:no_match, [], 'no known player named "wayne gretzky"'])
    end
  end

  describe "manual overrides (ADR 0029)" do
    let(:overrides) do
      SportsIngest::Identity::Overrides.new([
        {source: "evolving_hockey", source_id: "ELIAS.PETTERSSON2", canonical_id: "8483678"},
        {source: "puckpedia", source_name: "Sebastian Aho", canonical_id: "8478427"}
      ])
    end
    let(:matcher) { described_class.new([pettersson_c, pettersson_d, aho_car, aho_nyi, stutzle], overrides: overrides) }

    it "beats an automatic match that conflicts with it" do
      # Birth date says the centre, but the source ID says the defenceman.
      match = matcher.match(source: :evolving_hockey, id: "ELIAS.PETTERSSON2", name: "Elias Pettersson",
        birth_date: "1998-11-12", position: "C", team: "VAN")

      expect([match.ref.canonical_id, match.confidence, match.reason]).to eq(["8483678", :exact, :override])
      expect(match.ref.source_id(:evolving_hockey)).to eq("ELIAS.PETTERSSON2")
    end

    it "applies a name override to records without an ID, whatever their position or team" do
      match = matcher.match(source: :puckpedia, name: "Sebastian Aho", position: "D", team: "NYI")

      expect([match.ref.canonical_id, match.reason]).to eq(["8478427", :override])
    end

    it "takes precedence over the source's own ID" do
      other = SportsIngest::Identity::Overrides.new([
        {source: "espn", source_id: 3900169, canonical_id: "8480222"}
      ])
      match = described_class.new([aho_car, aho_nyi], overrides: other).match(source: :espn, id: 3900169, name: "Sebastian Aho")

      expect(match.ref.canonical_id).to eq("8480222")
    end

    it "names a player who isn't among the known players, with the source ID added" do
      other = SportsIngest::Identity::Overrides.new([
        {source: "evolving_hockey", source_id: "NEW.PLAYER1", canonical_id: "8999999"}
      ])
      match = described_class.new([stutzle], overrides: other).match(source: :evolving_hockey, id: "NEW.PLAYER1", name: "New Player")

      expect([match.ref.canonical_id, match.ref.source_id(:evolving_hockey), match.reason]).to eq(["8999999", "NEW.PLAYER1", :override])
    end

    it "leaves records alone that no override covers" do
      match = matcher.match(source: :evolving_hockey, name: "Elias Pettersson", position: "C", team: "VAN")

      expect([match.ref.canonical_id, match.reason]).to eq(["8480012", :name_position_team])
    end

    it "refuses an override whose canonical ID isn't valid for the sport" do
      bad = SportsIngest::Identity::Overrides.new([{source: "x", source_id: "A", canonical_id: "not-an-id"}])

      expect { described_class.new([stutzle], overrides: bad) }.to raise_error(ArgumentError, /valid hockey canonical ID/)
    end
  end

  describe "building" do
    it "keeps a player listed twice once" do
      expect(described_class.new([stutzle, stutzle]).match(source: :x, name: "Tim Stutzle").reason).to eq(:unique_name)
    end

    it "accepts players with unknown bio fields" do
      bare = Struct.new(:ref, :full_name, :birth_date, :position, :team)
        .new(SportsIngest::Identity::PlayerRef.new(sport: :hockey, canonical_id: 1), "A Player", nil, nil, nil)

      expect(described_class.new([bare]).match(source: :x, name: "A Player", position: "C", team: "EDM").reason)
        .to eq(:unique_name)
    end

    it "raises for no players, mixed sports or a shared source ID" do
      football = Struct.new(:ref, :full_name, :birth_date, :position, :team)
        .new(SportsIngest::Identity::PlayerRef.new(sport: :football, canonical_id: "00-0033873"), "P M", nil, "QB", "KC")
      clash = player(1, "A", "B", "C", "EDM", nil, source_ids: {espn: 3900169})

      expect { described_class.new([]) }.to raise_error(ArgumentError, /at least one/)
      expect { described_class.new([stutzle, football]) }.to raise_error(ArgumentError, /span sports/)
      expect { described_class.new([aho_car, clash]) }.to raise_error(ArgumentError, /espn ID 3900169/)
    end

    it "raises ArgumentError for a bad birth date" do
      expect { matcher.match(source: :x, name: "Tim Stutzle", birth_date: "soon") }.to raise_error(ArgumentError, /ISO 8601/)
    end
  end
end

RSpec.describe SportsIngest::Identity::Match do
  let(:ref) { {sport: :hockey, canonical_id: 8478402} }

  it "derives the confidence from the reason and round-trips through JSON" do
    match = described_class.new(ref: ref, reason: :name_and_birth_date, detail: "x")

    expect(match.confidence).to eq(:high)
    expect(described_class.from_h(JSON.parse(match.to_json, symbolize_names: true))).to eq(match)
  end

  it "raises for an unknown reason, a disagreeing confidence or a missing ref" do
    expect { described_class.new(ref: ref, reason: :guess, detail: "") }.to raise_error(ArgumentError, /reason/)
    expect { described_class.new(ref: ref, reason: :unique_name, detail: "", confidence: :high) }
      .to raise_error(ArgumentError, /confidence/)
    expect { described_class.new(ref: nil, reason: :unique_name, detail: "") }.to raise_error(ArgumentError, /needs a ref/)
    expect { described_class.new(ref: ref, reason: :ambiguous, detail: "") }.to raise_error(ArgumentError, /can't have/)
  end
end
