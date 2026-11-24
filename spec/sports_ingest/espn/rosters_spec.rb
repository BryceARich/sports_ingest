# frozen_string_literal: true

require "sports_ingest/espn"

RSpec.describe SportsIngest::ESPN::Rosters do
  subject(:rosters) { described_class.new(client: client, processed: processed) }

  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.raw_cache = :off } }
  let(:limiter) { SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}) }
  let(:http) do
    SportsIngest::HTTP::Client.new(source: :espn, rate_limiter: limiter, max_retries: 0, configuration: config)
  end
  let(:client) { SportsIngest::ESPN::Client.new(game: :hockey, http: http, configuration: config) }
  let(:processed) { SportsIngest::Cache::Processed.new(store: SportsIngest::Cache::MemoryStore.new) }
  let(:league_url) { "https://lm-api-reads.fantasy.espn.com/apis/v3/games/fhl/seasons/2027/segments/0/leagues/12345" }
  let(:requested_url) { "#{league_url}?view=mTeam&view=mRoster" }
  let(:json) { {"Content-Type" => "application/json;charset=utf-8"} }

  # Invented values in ESPN's real shape: a league with two teams and the mTeam and mRoster views.
  let(:player) do
    {"id" => 4_001, "fullName" => "Sample Winger", "proTeamId" => 20, "defaultPositionId" => 3,
     "injuryStatus" => "ACTIVE"}
  end
  let(:free_agent) do
    {"id" => 4_002, "fullName" => "Sample Goalie", "proTeamId" => 0, "defaultPositionId" => 5}
  end
  let(:payload) do
    {
      "id" => 12_345,
      "teams" => [
        {"id" => 1, "location" => "Sample", "nickname" => "Rays", "abbrev" => "SMP",
         "owners" => ["{OWNER-GUID-1}"],
         "roster" => {"entries" => [
           {"playerId" => 4_001, "lineupSlotId" => 0, "acquisitionType" => "DRAFT",
            "playerPoolEntry" => {"id" => 4_001, "player" => player}},
           {"playerId" => 4_002, "lineupSlotId" => 21, "acquisitionType" => "ADD",
            "playerPoolEntry" => {"id" => 4_002, "player" => free_agent}}
         ]}},
        {"id" => 2, "location" => "", "nickname" => "Blue", "abbrev" => "BLU", "owners" => [],
         "roster" => {"entries" => []}}
      ]
    }
  end

  def stub_league(body = payload, status: 200)
    stub_request(:get, requested_url).to_return(status: status, headers: json, body: body.to_json)
  end

  describe "#fetch" do
    before { stub_league }

    it "requests the mTeam and mRoster views" do
      rosters.fetch(12_345, season: 2027)

      expect(a_request(:get, requested_url)).to have_been_made.once
    end

    it "returns a FantasyTeam per team, in ESPN's order" do
      teams = rosters.fetch(12_345, season: 2027)

      expect(teams).to all(be_a(SportsIngest::ESPN::FantasyTeam))
      expect(teams.map(&:id)).to eq([1, 2])
      expect(teams.first.name).to eq("Sample Rays")
      expect(teams.first.abbrev).to eq("SMP")
      expect(teams.first.owner_ids).to eq(["{OWNER-GUID-1}"])
    end

    it "uses the team's name parts that are present" do
      expect(rosters.fetch(12_345, season: 2027).last.name).to eq("Blue")
    end

    it "maps roster entries, with the real team's tri-code from the Teams table" do
      entry = rosters.fetch(12_345, season: 2027).first.entries.first

      expect(entry).to be_a(SportsIngest::ESPN::RosterEntry)
      expect(entry.player_id).to eq(4_001)
      expect(entry.full_name).to eq("Sample Winger")
      expect(entry.lineup_slot_id).to eq(0)
      expect(entry.default_position_id).to eq(3)
      expect(entry.pro_team_id).to eq(20)
      expect(entry.pro_team).to eq(SportsIngest::Teams.find_by_source_id(:espn, 20).tri_code)
      expect(entry.injury_status).to eq("ACTIVE")
      expect(entry.acquisition_type).to eq("DRAFT")
    end

    it "leaves pro_team nil for a free agent" do
      entry = rosters.fetch(12_345, season: 2027).first.entries.last

      expect(entry.pro_team_id).to eq(0)
      expect(entry.pro_team).to be_nil
    end

    it "keeps an empty roster as an empty list" do
      expect(rosters.fetch(12_345, season: 2027).last.entries).to eq([])
    end

    it "writes the teams to the processed cache, keyed by league and season" do
      rosters.fetch(12_345, season: 2027)

      entry = processed.read("espn/fhl/leagues/12345/2027/teams", model: SportsIngest::ESPN::FantasyTeam)
      expect(entry.models.map(&:id)).to eq([1, 2])
      expect(entry.models.first.entries.first.pro_team).to eq(SportsIngest::Teams.find_by_source_id(:espn, 20).tri_code)
    end

    it "raises ArgumentError for a league or season that isn't a positive Integer" do
      expect { rosters.fetch(0, season: 2027) }.to raise_error(ArgumentError, /league_id/)
      expect { rosters.fetch(12_345, season: "2027") }.to raise_error(ArgumentError, /season/)
    end
  end

  describe "#fetch errors" do
    it "raises AuthError with a cookie hint for a private league" do
      stub_league({"messages" => ["You are not authorized to view this League."]}, status: 401)

      expect { rosters.fetch(12_345, season: 2027) }.to raise_error(SportsIngest::AuthError, /espn_s2/)
    end

    it "raises NotFound for an unknown league" do
      stub_league({"messages" => ["Not Found"]}, status: 404)

      expect { rosters.fetch(12_345, season: 2027) }.to raise_error(SportsIngest::NotFound)
    end

    it "raises SourceChangedError when the league has no teams" do
      stub_league({"id" => 12_345})

      expect { rosters.fetch(12_345, season: 2027) }
        .to raise_error(SportsIngest::SourceChangedError, /no "teams"/)
    end

    it "raises SourceChangedError when a team has no roster, the mRoster view being missing" do
      stub_league({"teams" => [{"id" => 1, "location" => "Sample", "nickname" => "Rays"}]})

      expect { rosters.fetch(12_345, season: 2027) }
        .to raise_error(SportsIngest::SourceChangedError, /mRoster view/)
    end

    it "raises SourceChangedError when a roster entry has no player ID" do
      stub_league({"teams" => [{"id" => 1, "roster" => {"entries" => [{"lineupSlotId" => 0}]}}]})

      expect { rosters.fetch(12_345, season: 2027) }
        .to raise_error(SportsIngest::SourceChangedError, /no player ID/)
    end
  end
end
