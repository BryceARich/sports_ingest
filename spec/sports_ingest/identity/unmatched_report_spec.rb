# frozen_string_literal: true

require "sports_ingest"

RSpec.describe SportsIngest::Identity::UnmatchedReport do
  # Duck-typed known players, as the matcher reads them.
  known = Struct.new(:ref, :full_name, :birth_date, :position, :team)
  let(:matcher) do
    SportsIngest::Identity::Matcher.new([
      known.new(SportsIngest::Identity::PlayerRef.new(sport: :hockey, canonical_id: 8480012), "Elias Pettersson",
        "1998-11-12", "C", "VAN"),
      known.new(SportsIngest::Identity::PlayerRef.new(sport: :hockey, canonical_id: 8483678), "Elias Pettersson",
        "2004-02-16", "D", "VAN"),
      known.new(SportsIngest::Identity::PlayerRef.new(sport: :hockey, canonical_id: 8478427), "Sebastian Aho",
        "1997-07-26", "C", "CAR"),
      known.new(SportsIngest::Identity::PlayerRef.new(sport: :hockey, canonical_id: 8480222), "Sebastian Aho",
        "1996-02-17", "D", "NYI"),
      known.new(SportsIngest::Identity::PlayerRef.new(sport: :hockey, canonical_id: 8482116), "Tim Stützle",
        "2002-01-15", "C", "OTT")
    ])
  end

  let(:records) do
    [
      {source: :evolving_hockey, name: "Tim Stutzle"},
      {source: :evolving_hockey, name: "Elias Pettersson", position: "C", team: "VAN"},
      {source: :evolving_hockey, name: "Sebastian Aho"},
      {source: :evolving_hockey, name: "Nobody Known", position: "D", team: "BOS"},
      {source: :evolving_hockey, name: "Tim Stutzle", birth_date: "2002-01-15"}
    ]
  end

  subject(:report) { described_class.build(matcher, records) }

  it "keeps every record, in order" do
    expect(report.rows.map(&:name)).to eq(["Tim Stutzle", "Elias Pettersson", "Sebastian Aho", "Nobody Known", "Tim Stutzle"])
  end

  it "leaves out records matched confidently" do
    expect(report.review.map(&:name)).to eq(["Tim Stutzle", "Sebastian Aho", "Nobody Known"])
  end

  it "reports a unique name as low confidence, with the matched player" do
    row = report.review.first.match
    expect([row.confidence, row.reason, row.ref.canonical_id]).to eq([:low, :unique_name, "8482116"])
  end

  it "lists the candidates for an ambiguous record" do
    aho = report.review[1].match
    expect([aho.confidence, aho.reason, aho.candidates.map(&:canonical_id)]).to eq([:none, :ambiguous, %w[8478427 8480222]])
  end

  it "lists nothing as candidates when no known player shares the name" do
    expect(report.review.last.match.candidates).to eq([])
  end

  describe "#to_text" do
    it "summarizes the counts and lists each record that needs review" do
      expect(report.to_text).to eq(
        "Identity report: 5 records, 3 to review\n" \
        "  [low] evolving_hockey Tim Stutzle  -> hockey:8482116  matched on the only \"tim stutzle\"\n" \
        "  [none] evolving_hockey Sebastian Aho  unmatched  2 players match the only \"sebastian aho\"" \
        "  candidates: hockey:8478427, hockey:8480222\n" \
        "  [none] evolving_hockey Nobody Known (D) BOS  unmatched  no known player named \"nobody known\"\n"
      )
    end

    it "says so when nothing needs review" do
      clean = described_class.build(matcher, [{source: :x, name: "Tim Stutzle", birth_date: "2002-01-15"}])
      expect(clean.to_text).to eq("Identity report: 1 records, 0 to review\n")
    end
  end

  describe "#to_csv" do
    it "writes a header and one quoted row per record that needs review" do
      csv = described_class.build(matcher, [{source: :x, name: "Nobody, Known", team: "BOS"}]).to_csv

      expect(csv).to eq(
        "source,name,id,position,team,confidence,reason,detail,candidates\n" \
        "x,\"Nobody, Known\",,,BOS,none,no_match,\"no known player named \"\"known nobody\"\"\",\n"
      )
    end
  end

  it "raises ArgumentError for a record without a source" do
    expect { described_class.build(matcher, [{name: "Tim Stutzle"}]) }.to raise_error(KeyError)
  end
end
