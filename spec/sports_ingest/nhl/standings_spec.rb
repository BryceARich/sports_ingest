# frozen_string_literal: true

require "json"
require "sports_ingest/nhl"

RSpec.describe SportsIngest::NHL::Standings do
  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.raw_cache = :off } }
  let(:http) do
    SportsIngest::HTTP::Client.new(source: :nhl, max_retries: 0, configuration: config,
      rate_limiter: SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}))
  end
  let(:client) { SportsIngest::NHL::Client.new(http: http) }
  let(:url) { "https://api-web.nhle.com/v1/standings" }

  def row(**overrides)
    record = %w[GamesPlayed Wins Losses OtLosses Points RegulationWins RegulationPlusOtWins GoalsFor GoalsAgainst]
    splits = %w[home road l10].product(record).to_h { |prefix, suffix| ["#{prefix}#{suffix}", 1] }
    {
      "date" => "2026-11-22", "seasonId" => 20262027, "teamAbbrev" => {"default" => "TBL"},
      "teamName" => {"default" => "Tampa Bay Lightning"}, "conferenceName" => "Eastern",
      "divisionName" => "Atlantic", "leagueSequence" => 1, "conferenceSequence" => 1,
      "divisionSequence" => 1, "wildcardSequence" => 0, "gamesPlayed" => 2, "wins" => 2,
      "losses" => 0, "otLosses" => 0, "ties" => 0, "points" => 4, "pointPctg" => 1,
      "regulationWins" => 2, "regulationPlusOtWins" => 2, "shootoutWins" => 0,
      "shootoutLosses" => 0, "goalFor" => 7, "goalAgainst" => 2, "goalDifferential" => 5,
      "streakCode" => "W", "streakCount" => 2
    }.merge(splits).merge(overrides)
  end

  def payload(*rows)
    {"wildCardIndicator" => true, "standingsDateTimeUtc" => "2026-11-23T23:09:46Z", "standings" => rows}
  end

  describe ".fetch", vcr: {cassette_name: "nhl/standings_2026_11_22"} do
    subject(:standings) { described_class.fetch(date: Date.new(2026, 11, 22), client: client) }

    it "parses the recorded standings" do
      expect(standings).to have_attributes(date: Date.new(2026, 11, 22), season: 2026,
        updated_at: Time.utc(2026, 11, 23, 23, 9, 46), wild_card: true)
      expect(standings.teams.size).to eq(32)
      expect(standings.teams.map(&:league_rank)).to eq((1..32).to_a)
      expect(standings.teams).to all(have_attributes(team_id: a_string_matching(/\A\d+\z/)))
    end

    it "maps one team's line" do
      expect(standings.find("CAR")).to have_attributes(
        team_id: "12", tri_code: "CAR", team_name: "Carolina Hurricanes", conference: "Eastern",
        division: "Metropolitan", league_rank: 1, conference_rank: 1, division_rank: 1,
        wildcard_rank: nil, clinch_indicator: nil, games_played: 24, wins: 18, losses: 3,
        ot_losses: 3, points: 39, point_pct: 0.8125, regulation_wins: 17,
        regulation_plus_ot_wins: 18, goals_for: 100, goals_against: 55, goal_differential: 45,
        streak_code: "W", streak_count: 2, record: "18-3-3"
      )
      expect(standings.find("CAR").home).to have_attributes(games_played: 11, wins: 8, losses: 1,
        ot_losses: 2, points: 18)
      expect(standings.find("CAR").last_10).to have_attributes(games_played: 10, wins: 8, points: 17)
    end

    it "keeps wild-card places and resolves NY Rangers by tri-code" do
      expect(standings.find("NYR")).to have_attributes(team_name: "New York Rangers", division_rank: 4,
        wildcard_rank: 3)
    end

    it "groups by division and conference, best first" do
      metro = standings.division("metropolitan")
      expect(metro.size).to eq(8)
      expect(metro.map(&:division_rank)).to eq((1..8).to_a)
      expect(metro.first.tri_code).to eq("CAR")
      expect(standings.conference("Western").size).to eq(16)
    end

    it "finds a team by another source's code" do
      expect(standings.find("T.B")&.tri_code).to eq("TBL")
    end

    it "round-trips through JSON" do
      expect(described_class.from_h(JSON.parse(standings.to_json))).to eq(standings)
    end
  end

  describe ".fetch with no date" do
    it "asks for /standings/now" do
      stub_request(:get, "#{url}/now").to_return(status: 200, headers: {"Content-Type" => "application/json"},
        body: payload(row).to_json)

      expect(described_class.fetch(client: client).find("TBL").points).to eq(4)
    end
  end

  describe ".fetch with a bad date" do
    it "rejects anything but a Date or YYYY-MM-DD" do
      expect { described_class.fetch(date: "11/22/2026", client: client) }.to raise_error(ArgumentError, /YYYY-MM-DD/)
      expect { described_class.fetch(date: "2026-02-30", client: client) }.to raise_error(ArgumentError, /valid/)
    end
  end

  describe ".from_payload" do
    it "uses the date asked for when the payload has no teams" do
      standings = described_class.from_payload(payload, date: "2026-07-15")

      expect(standings).to have_attributes(date: Date.new(2026, 7, 15), season: nil, teams: [])
    end

    it "keeps the clinch letter and a missing streak" do
      standing = described_class.from_payload(payload(row("clinchIndicator" => "x", "streakCode" => nil,
        "streakCount" => nil))).teams.first

      expect(standing).to have_attributes(clinch_indicator: "x", clinched?: true, eliminated?: false,
        streak_code: nil, streak_count: nil)
    end

    it "leaves team_id nil for a code the team table doesn't know" do
      standing = described_class.from_payload(payload(row("teamAbbrev" => {"default" => "XYZ"}))).teams.first

      expect(standing).to have_attributes(tri_code: "XYZ", team_id: nil)
    end

    it "raises SourceChangedError when a field is missing or retyped" do
      expect { described_class.from_payload(payload(row.except("points"))) }
        .to raise_error(SportsIngest::SourceChangedError, /"points"/)
      expect { described_class.from_payload(payload(row("wins" => "2"))) }
        .to raise_error(SportsIngest::SourceChangedError, /wins should be Integer/)
      expect { described_class.from_payload({"standings" => {}}) }
        .to raise_error(SportsIngest::SourceChangedError, /no standings list/)
      expect { described_class.from_payload(payload(row("seasonId" => 2026))) }
        .to raise_error(SportsIngest::SourceChangedError, /seasonId/)
    end
  end
end
