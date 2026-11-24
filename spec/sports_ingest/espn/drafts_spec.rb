# frozen_string_literal: true

require "sports_ingest/espn"

RSpec.describe SportsIngest::ESPN::Drafts do
  subject(:drafts) { described_class.new(client: client) }

  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.raw_cache = :off } }
  let(:limiter) { SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}) }
  let(:http) do
    SportsIngest::HTTP::Client.new(source: :espn, rate_limiter: limiter, max_retries: 0, configuration: config)
  end
  let(:client) { SportsIngest::ESPN::Client.new(game: :hockey, http: http, configuration: config) }
  let(:base) { "https://lm-api-reads.fantasy.espn.com/apis/v3/games/fhl" }
  let(:json) { {"Content-Type" => "application/json;charset=utf-8"} }

  # Invented values in ESPN's mDraftDetail shape. Picks are out of order to check sorting.
  let(:detail) do
    {
      "drafted" => true,
      "inProgress" => false,
      "picks" => [
        {"overallPickNumber" => 2, "roundId" => 1, "roundPickNumber" => 2, "teamId" => 4,
         "playerId" => 3_001, "keeper" => false},
        {"overallPickNumber" => 1, "roundId" => 1, "roundPickNumber" => 1, "teamId" => 7,
         "playerId" => 3_002, "keeper" => true},
        {"overallPickNumber" => 3, "roundId" => 1, "roundPickNumber" => 3, "teamId" => 1,
         "playerId" => 3_003}
      ]
    }
  end

  def league_with(detail_hash)
    {"id" => 12_345, "seasonId" => 2026, "draftDetail" => detail_hash}
  end

  describe "#fetch" do
    it "reads the draft from the league with the mDraftDetail view, in pick order" do
      stub_request(:get, "#{base}/seasons/2027/segments/0/leagues/12345?view=mDraftDetail")
        .to_return(status: 200, headers: json, body: league_with(detail).to_json)

      draft = drafts.fetch(12_345, season: 2027)

      expect(draft.season).to eq(2027)
      expect(draft.drafted).to be(true)
      expect(draft.in_progress).to be(false)
      expect(draft.picks.map(&:overall_pick)).to eq([1, 2, 3])
      expect(draft.picks.first).to eq(SportsIngest::ESPN::DraftPick.new(overall_pick: 1, round: 1, round_pick: 1,
        team_id: 7, player_id: 3_002, keeper: true))
    end
  end

  describe "#history" do
    let(:history_url) { "#{base}/leagueHistory/12345" }
    let(:history_query) { {"seasonId" => "2026", "view" => "mDraftDetail"} }

    it "returns the draft for the requested season from the league's history" do
      other_season = league_with(detail).merge("seasonId" => 2025)
      stub_request(:get, history_url).with(query: history_query)
        .to_return(status: 200, headers: json,
          body: [other_season, league_with(detail)].to_json)

      draft = drafts.history(12_345, season: 2026)

      expect(draft.season).to eq(2026)
      expect(draft.picks.map(&:player_id)).to eq([3_002, 3_001, 3_003])
      expect(draft.keepers.map(&:player_id)).to eq([3_002])
    end

    it "raises NotFound when the history has no such season" do
      stub_request(:get, history_url).with(query: history_query)
        .to_return(status: 200, headers: json, body: [league_with(detail).merge("seasonId" => 2025)].to_json)

      expect { drafts.history(12_345, season: 2026) }
        .to raise_error(SportsIngest::NotFound, /no history for season 2026/)
    end

    it "raises SourceChangedError when the history isn't an array" do
      stub_request(:get, history_url).with(query: history_query)
        .to_return(status: 200, headers: json, body: league_with(detail).to_json)

      expect { drafts.history(12_345, season: 2026) }
        .to raise_error(SportsIngest::SourceChangedError, /leagueHistory should be a JSON array/)
    end
  end

  describe "#parse" do
    it "marks an unstarted draft with no picks" do
      draft = drafts.parse(league_with({"drafted" => false, "inProgress" => false, "picks" => []}), season: 2027)

      expect(draft.drafted).to be(false)
      expect(draft.picks).to eq([])
      expect(draft.keepers).to eq([])
    end

    it "raises SourceChangedError when there is no draftDetail, as when the view was left out" do
      expect { drafts.parse({"id" => 12_345}, season: 2027) }
        .to raise_error(SportsIngest::SourceChangedError, /no draftDetail/)
    end

    it "raises SourceChangedError when a pick is missing a field" do
      broken = {"picks" => [{"overallPickNumber" => 1, "roundId" => 1, "teamId" => 2, "playerId" => 3}]}

      expect { drafts.parse(league_with(broken), season: 2027) }
        .to raise_error(SportsIngest::SourceChangedError, /roundPickNumber/)
    end
  end
end
