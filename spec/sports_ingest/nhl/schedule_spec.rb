# frozen_string_literal: true

require "sports_ingest/nhl"

RSpec.describe SportsIngest::NHL::Schedule do
  subject(:schedule) { described_class.new(client: client) }

  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.raw_cache = :off } }
  let(:limiter) { SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}) }
  let(:http) do
    SportsIngest::HTTP::Client.new(source: :nhl, rate_limiter: limiter, max_retries: 0, configuration: config)
  end
  let(:client) { SportsIngest::NHL::Client.new(http: http) }
  let(:base) { "https://api-web.nhle.com/v1" }
  let(:json) { {"Content-Type" => "application/json"} }

  def matchup(game)
    "#{game.away_team.tri_code}@#{game.home_team.tri_code}"
  end

  def stub_week(date, body)
    stub_request(:get, "#{base}/schedule/#{date}").to_return(status: 200, headers: json, body: JSON.generate(body))
  end

  def game_json(**overrides)
    {"id" => 2026020001, "season" => 20262027, "gameType" => 2, "startTimeUTC" => "2026-11-24T00:00:00Z",
     "gameState" => "FUT", "gameScheduleState" => "OK", "venue" => {"default" => "Arena"},
     "homeTeam" => {"id" => 10, "abbrev" => "TOR"}, "awayTeam" => {"id" => 8, "abbrev" => "MTL"}}.merge(overrides)
  end

  # One interaction per week (2026-11-16 and 2026-11-23), shared by these examples: a date only
  # needs the first, and the team filter reads the range twice. Re-recording writes a copy per
  # request, so keep one of each afterwards.
  describe "recorded payloads",
    vcr: {cassette_name: "nhl/schedule_weeks_2026_11_16_and_23", allow_unused_http_interactions: true,
          allow_playback_repeats: true} do
    it "returns one date's games as Game models" do
      games = SportsIngest::NHL.schedule(date: "2026-11-16", client: client)

      expect(games).not_to be_empty
      expect(games).to all(be_a(SportsIngest::NHL::Game))
      expect(games.map(&:date).uniq).to eq([Date.new(2026, 11, 16)])
      expect(games.map(&:season).uniq).to eq([2026])
      expect(games.map(&:start_time)).to eq(games.map(&:start_time).sort)
    end

    it "fills in scores and how finished games ended" do
      game = schedule.on(Date.new(2026, 11, 16)).find(&:final?)

      expect(game.home_team.score).to be_a(Integer)
      expect(game.away_team.score).to be_a(Integer)
      expect(%i[regulation overtime shootout]).to include(game.ended_in)
      expect(game.home_team.team).to be_a(SportsIngest::Team)
    end

    it "follows nextStartDate across weeks and keeps only the range" do
      games = schedule.between("2026-11-16", "2026-11-24")

      expect(games.map(&:date).uniq.sort).to eq((Date.new(2026, 11, 16)..Date.new(2026, 11, 24)).select do |day|
        games.any? { |g| g.date == day }
      end)
      expect(games.map(&:date).minmax).to eq([Date.new(2026, 11, 16), Date.new(2026, 11, 24)])
      expect(a_request(:get, "#{base}/schedule/2026-11-23")).to have_been_made.once
    end

    it "filters a range to one team, by any of its codes" do
      leafs = SportsIngest::Teams.fetch("TOR")
      games = schedule.between("2026-11-16", "2026-11-24", team: "tor")

      expect(games).not_to be_empty
      expect(games).to all(satisfy { |g| g.involves?(leafs) })
      expect(games).to eq(schedule.between("2026-11-16", "2026-11-24", team: leafs))
    end

    it "round-trips through the processed cache" do
      games = schedule.on("2026-11-16")
      cache = SportsIngest::Cache::Processed.new(store: SportsIngest::Cache::MemoryStore.new)

      cache.write("nhl/schedule/2026-11-16", games, source: :nhl)

      expect(cache.read("nhl/schedule/2026-11-16", model: SportsIngest::NHL::Game).models).to eq(games)
    end
  end

  describe "#for_team", vcr: {cassette_name: "nhl/club_schedule_season_tor_20262027"} do
    it "returns a team's season, preseason included" do
      games = SportsIngest::NHL.schedule(team: "TOR", season: 2026, client: client)

      expect(games.count { |g| g.game_type == :regular }).to eq(84)
      expect(games.map(&:game_type).uniq).to include(:preseason)
      expect(games).to all(satisfy { |g| g.involves?("10") })
      expect(games.first.date).to eq(Date.new(2026, 9, 19))
    end
  end

  describe "#fetch" do
    it "rejects keyword combinations it doesn't take" do
      [{}, {date: "2026-11-16", from: "2026-11-16", to: "2026-11-17"}, {from: "2026-11-16"},
        {season: 2026}, {season: 2026, team: "TOR", date: "2026-11-16"}].each do |args|
        expect { schedule.fetch(**args) }.to raise_error(ArgumentError), args.inspect
      end
    end
  end

  it "rejects a bad date or reversed range before any request" do
    expect { schedule.on("11/16/2026") }.to raise_error(ArgumentError, /YYYY-MM-DD/)
    expect { schedule.between("2026-11-17", "2026-11-16") }.to raise_error(ArgumentError, /after/)
    expect { schedule.for_team("TOR", season: 20262027.0) }.to raise_error(ArgumentError, /season/)
  end

  it "raises NotFound for an unknown team" do
    expect { schedule.for_team("XYZ", season: 2026) }.to raise_error(SportsIngest::NotFound)
  end

  it "stops when the week has no nextStartDate" do
    stub_week("2026-11-16", {"gameWeek" => [{"date" => "2026-11-16", "games" => [game_json]}]})
    stub_week("2026-11-23", {"gameWeek" => [{"date" => "2026-11-23", "games" => []}]})

    expect(schedule.between("2026-11-16", "2026-11-23").map(&:id)).to eq(["2026020001"])
  end

  it "maps game types, states and outcomes" do
    stub_week("2026-11-16", {"gameWeek" => [{"date" => "2026-11-16", "games" => [
      game_json("gameType" => 3, "gameState" => "OFF", "gameOutcome" => {"lastPeriodType" => "SO"},
        "homeTeam" => {"id" => 10, "abbrev" => "TOR", "score" => 3},
        "awayTeam" => {"id" => 8, "abbrev" => "MTL", "score" => 2})
    ]}], "nextStartDate" => "2026-11-23"})

    game = schedule.on("2026-11-16").first

    expect(game).to have_attributes(game_type: :playoffs, state: :final, ended_in: :shootout, schedule_state: :ok,
      venue: "Arena", neutral_site: false)
    expect([game.home_team.score, game.away_team.score]).to eq([3, 2])
  end

  it "raises SourceChangedError when a game isn't shaped as expected" do
    stub_week("2026-11-16", {"gameWeek" => [{"date" => "2026-11-16", "games" => [game_json("gameState" => "NEW")]}]})
    expect { schedule.on("2026-11-16") }.to raise_error(SportsIngest::SourceChangedError, /NEW/)
  end

  it "raises SourceChangedError when the week is missing" do
    stub_week("2026-11-16", {"weeks" => []})
    expect { schedule.on("2026-11-16") }.to raise_error(SportsIngest::SourceChangedError, /gameWeek/)
  end
end
