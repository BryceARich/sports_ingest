# frozen_string_literal: true

RSpec.describe SportsIngest::Teams do
  let(:teams) { described_class.all }

  it "has the 32 NHL teams, sorted by tri-code" do
    expect(teams.size).to eq(32)
    expect(teams.map(&:tri_code)).to eq(teams.map(&:tri_code).sort)
    expect(teams.map(&:id).uniq.size).to eq(32)
    expect(teams).to be_frozen
  end

  it "splits the teams into two conferences of 16 and four divisions of 8" do
    expect(teams.group_by(&:conference).transform_values(&:size)).to eq("Eastern" => 16, "Western" => 16)
    expect(teams.group_by(&:division).transform_values(&:size))
      .to eq("Atlantic" => 8, "Metropolitan" => 8, "Central" => 8, "Pacific" => 8)
  end

  %i[nhl evolving_hockey puckpedia espn].each do |source|
    it "resolves all 32 teams from their #{source} codes" do
      teams.each do |team|
        expect(team.codes_for(source)).not_to be_empty, "#{team.tri_code} has no #{source} code"
        team.codes_for(source).each do |code|
          expect(described_class.fetch(code, source: source)).to eq(team)
          expect(described_class.fetch(code)).to eq(team)
        end
      end
    end
  end

  it "maps the codes the sources disagree on" do
    {
      "TBL" => ["T.B", "TB"], "NJD" => ["N.J", "NJ"], "LAK" => ["L.A", "LA"],
      "SJS" => ["S.J", "SJ"], "UTA" => ["UTA", "UTAH"]
    }.each do |tri_code, (eh, espn)|
      expect(described_class.fetch(eh, source: :evolving_hockey).tri_code).to eq(tri_code)
      expect(described_class.fetch(espn, source: :espn).tri_code).to eq(tri_code)
    end
  end

  it "ignores case, spaces, punctuation and accents" do
    expect(described_class.fetch(" t.b ").tri_code).to eq("TBL")
    expect(described_class.fetch(:sjs).tri_code).to eq("SJS")
    expect(described_class.fetch("Montreal Canadiens").tri_code).to eq("MTL")
    expect(described_class.fetch("st louis blues").tri_code).to eq("STL")
  end

  it "matches only the given source's codes when a source is given" do
    expect(described_class.find("LAK", source: :espn)).to be_nil
    expect(described_class.find("LA", source: :nhl)).to be_nil
    expect(described_class.find("Tampa Bay Lightning", source: :nhl)).to be_nil
  end

  it "returns nil from find and raises NotFound from fetch for an unknown code" do
    expect(described_class.find("XYZ")).to be_nil
    expect { described_class.fetch("XYZ") }.to raise_error(SportsIngest::NotFound, /"XYZ"/)
    expect { described_class.fetch("XYZ", source: :espn) }.to raise_error(SportsIngest::NotFound, /in espn/)
  end

  it "rejects unknown sources and sports" do
    expect { described_class.find("TBL", source: :yahoo) }.to raise_error(ArgumentError, /yahoo/)
    expect { described_class.all(sport: :football) }.to raise_error(ArgumentError, /football/)
  end

  it "finds a team by a source's ID" do
    expect(described_class.find_by_source_id(:nhl, 68).name).to eq("Utah Mammoth")
    expect(described_class.find_by_source_id("espn", "20").tri_code).to eq("TBL")
    expect(described_class.find_by_source_id(:nhl, 59)).to be_nil
  end

  it "gives every team well-formed colors" do
    teams.each do |team|
      expect(team.colors.keys).to eq(%i[primary secondary])
      expect(team.colors.values).to all(match(/\A#[0-9A-F]{6}\z/))
    end
  end

  describe "against the NHL's own team data" do
    let(:client) do
      SportsIngest::HTTP::Client.new(source: :nhl,
        rate_limiter: SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}))
    end

    it "matches the standings' codes, names, conferences and divisions",
      vcr: {cassette_name: "nhl/standings_2026_11_22"} do
      rows = JSON.parse(client.get("https://api-web.nhle.com/v1/standings/2026-11-22").body).fetch("standings")

      expect(rows.size).to eq(32)
      rows.each do |row|
        team = described_class.fetch(row.dig("teamAbbrev", "default"), source: :nhl)
        expect(team).to have_attributes(
          name: row.dig("teamName", "default"), common_name: row.dig("teamCommonName", "default"),
          conference: row.fetch("conferenceName"), division: row.fetch("divisionName")
        )
      end
    end

    it "matches the stats API's team IDs", vcr: {cassette_name: "nhl/stats_team"} do
      rows = JSON.parse(client.get("https://api.nhle.com/stats/rest/en/team").body).fetch("data")
      pairs = rows.map { |row| [row.fetch("id").to_s, row.fetch("triCode")] }

      teams.each do |team|
        expect(pairs).to include([team.id, team.tri_code])
        expect(rows.find { |row| row.fetch("id").to_s == team.id }.fetch("fullName")).to eq(team.name)
      end
    end
  end
end
