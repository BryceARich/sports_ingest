# frozen_string_literal: true

require "sports_ingest/espn"

RSpec.describe SportsIngest::ESPN::LeagueSettings do
  subject(:league_settings) { described_class.new(client: client) }

  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.raw_cache = :off } }
  let(:limiter) { SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}) }
  let(:http) do
    SportsIngest::HTTP::Client.new(source: :espn, rate_limiter: limiter, max_retries: 0, configuration: config)
  end
  let(:client) { SportsIngest::ESPN::Client.new(game: :football, http: http, configuration: config) }
  let(:url) do
    "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/2026/segments/0/leagues/12345" \
      "?view=mSettings&view=mTeam"
  end
  # ESPN's default PPR league settings (public league defaults, 2026), with invented teams.
  let(:body) { File.read(File.expand_path("../../fixtures/espn/ffl_league_settings.json", __dir__)) }
  let(:payload) { JSON.parse(body) }

  describe ".new" do
    it "builds a client for the game" do
      expect(described_class.new(game: :hockey).client.game).to eq("fhl")
    end

    it "needs a game or a client" do
      expect { described_class.new }.to raise_error(ArgumentError, /game: or client:/)
    end
  end

  describe "#fetch" do
    before do
      stub_request(:get, url).to_return(status: 200, body: body,
        headers: {"Content-Type" => "application/json"})
    end

    it "asks for the mSettings and mTeam views" do
      league_settings.fetch(12_345, season: 2026)

      expect(a_request(:get, url)).to have_been_made.once
    end

    it "returns the league's identity" do
      expect(league_settings.fetch(12_345, season: 2026))
        .to include(league_id: 12_345, season: 2026, game: "ffl", name: "Invented Test League", size: 3,
          scoring_type: "H2H_POINTS")
    end

    it "maps stat IDs to points" do
      scoring = league_settings.fetch(12_345, season: 2026)[:scoring]

      expect(scoring).to include(3 => 0.04, 4 => 4.0, 20 => -2.0, 24 => 0.1, 53 => 1.0, 72 => -2.0, 85 => -1.0)
      expect(scoring.keys).to all(be_an(Integer))
      expect(scoring.values).to all(be_a(Float))
    end

    it "matches ESPN's PPR defaults when named through StatIds" do
      scoring = league_settings.fetch(12_345, season: 2026)[:scoring]
      named = scoring.to_h { |id, points| [SportsIngest::ESPN::StatIds.abbrev(:football, id), points] }

      expect(named).to include("PY" => 0.04, "PTD" => 4.0, "INT" => -2.0, "RY" => 0.1, "RTD" => 6.0,
        "REY" => 0.1, "RETD" => 6.0, "REC" => 1.0, "FUML" => -2.0, "FG0" => 3.0, "FG40" => 4.0,
        "FG50" => 5.0, "FG60" => 6.0, "FGM" => -1.0, "PAT" => 1.0)
      expect(scoring.keys.map { |id| SportsIngest::ESPN::StatIds.abbrev(:football, id) }).to all(be_a(String))
    end

    it "keeps per-slot points, such as D/ST points-allowed tiers" do
      settings = league_settings.fetch(12_345, season: 2026)

      expect(settings[:scoring_by_slot].keys).to eq(["D/ST"])
      expect(settings[:scoring_by_slot]["D/ST"]).to include(89 => 5.0, 92 => 1.0, 125 => -5.0, 136 => -7.0)
      expect(settings[:scoring][89]).to eq(0.0)
    end

    it "lists the roster slots that have a count" do
      expect(league_settings.fetch(12_345, season: 2026)[:roster_slots])
        .to eq("QB" => 1, "RB" => 2, "WR" => 2, "TE" => 1, "D/ST" => 1, "K" => 1, "BE" => 7, "IR" => 1, "FLEX" => 1)
    end

    it "lists teams with owners' display names and no member IDs" do
      settings = league_settings.fetch(12_345, season: 2026)

      expect(settings[:teams]).to eq([
        {id: 1, abbrev: "PUCK", name: "Pucks and Pigskins", owners: ["pucksandpigskins"]},
        {id: 2, abbrev: "GUS", name: "Gridiron Gus", owners: %w[gridirongus waiverwendy]},
        {id: 3, abbrev: "WW", name: "Waiver Wire Wonders", owners: []}
      ])
      expect(settings.to_s).not_to include("AAAA")
    end
  end

  describe "#parse" do
    let(:hockey) do
      described_class.new(client: SportsIngest::ESPN::Client.new(game: :hockey, http: http, configuration: config))
    end
    let(:category_league) do
      {
        "id" => 7, "seasonId" => 2027,
        "settings" => {
          "name" => "Cats", "size" => 0,
          "rosterSettings" => {"lineupSlotCounts" => {"3" => 9, "4" => 5, "5" => 2, "6" => 1, "7" => 5, "8" => 1,
                                                      "0" => 0, "9" => 2}},
          "scoringSettings" => {
            "scoringType" => "H2H_CATEGORY",
            "scoringItems" => [
              {"statId" => 13, "points" => 1.0, "isReverseItem" => false, "pointsOverrides" => {}},
              {"statId" => 10, "points" => 1.0, "isReverseItem" => true}
            ]
          }
        },
        "teams" => []
      }
    end

    it "reads a hockey category league, with reverse stats and unknown slots" do
      settings = hockey.parse(category_league)

      expect(settings).to include(game: "fhl", scoring_type: "H2H_CATEGORY", scoring: {13 => 1.0, 10 => 1.0},
        scoring_by_slot: {}, reverse_stat_ids: [10], teams: [])
      expect(settings[:roster_slots])
        .to eq("F" => 9, "D" => 5, "G" => 2, "UTIL" => 1, "BE" => 5, "IR" => 1, "slot_9" => 2)
    end

    it "raises SourceChangedError when settings are missing" do
      expect { league_settings.parse(payload.except("settings")) }
        .to raise_error(SportsIngest::SourceChangedError, /no "settings" object/)
    end

    it "raises SourceChangedError for a scoring item without a stat ID" do
      payload["settings"]["scoringSettings"]["scoringItems"] << {"points" => 1.0}

      expect { league_settings.parse(payload) }
        .to raise_error(SportsIngest::SourceChangedError, /Integer statId/)
    end

    it "raises SourceChangedError for non-numeric points" do
      payload["settings"]["scoringSettings"]["scoringItems"].first["points"] = "2"

      expect { league_settings.parse(payload) }.to raise_error(SportsIngest::SourceChangedError, /points/)
    end

    it "raises SourceChangedError for a payload that isn't an object" do
      expect { league_settings.parse([]) }.to raise_error(SportsIngest::SourceChangedError, /JSON object/)
    end
  end

  it "keeps inspect short" do
    expect(league_settings.inspect).to eq('#<SportsIngest::ESPN::LeagueSettings game="ffl">')
  end
end
