# frozen_string_literal: true

require "json"
require "sports_ingest/nhl"

RSpec.describe SportsIngest::NHL::Scoreboard do
  subject(:scoreboard) { described_class.new(client: client) }

  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.raw_cache = :off } }
  let(:http) do
    SportsIngest::HTTP::Client.new(source: :nhl, max_retries: 0, configuration: config,
      rate_limiter: SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}))
  end
  let(:client) { SportsIngest::NHL::Client.new(http: http) }
  let(:base) { "https://api-web.nhle.com/v1" }

  def game_json(**overrides)
    {"id" => 2026020373, "season" => 20262027, "gameType" => 2, "gameDate" => "2026-11-22",
     "startTimeUTC" => "2026-11-22T17:30:00Z", "gameState" => "OFF", "gameScheduleState" => "OK",
     "venue" => {"default" => "Madison Square Garden"}, "neutralSite" => false,
     "homeTeam" => {"id" => 3, "abbrev" => "NYR", "score" => 2, "sog" => 27},
     "awayTeam" => {"id" => 12, "abbrev" => "CAR", "score" => 5, "sog" => 41},
     "clock" => {"timeRemaining" => "00:00", "secondsRemaining" => 0, "running" => false, "inIntermission" => false},
     "period" => 3, "periodDescriptor" => {"number" => 3, "periodType" => "REG", "maxRegulationPeriods" => 3},
     "gameOutcome" => {"lastPeriodType" => "REG"}}.merge(overrides)
  end

  def stub_day(day, *games)
    stub_request(:get, "#{base}/score/#{day}")
      .to_return(status: 200, headers: {"Content-Type" => "application/json"},
        body: JSON.generate({"currentDate" => day, "games" => games}))
  end

  describe "today's recorded scoreboard", vcr: {cassette_name: "nhl/score_now_2026_11_23"} do
    subject(:scores) { SportsIngest::NHL.scores(client: client) }

    it "returns every game of the NHL's current date in one request" do
      expect(scores).not_to be_empty
      expect(scores).to all(be_a(SportsIngest::NHL::GameScore))
      expect(scores.map { |s| s.game.date }.uniq).to eq([Date.new(2026, 11, 23)])
      expect(scores.map { |s| s.game.start_time }).to eq(scores.map { |s| s.game.start_time }.sort)
      expect(a_request(:get, "#{base}/score/now")).to have_been_made.once
    end

    it "gives a live game its score, period and clock" do
      live = scores.find(&:live?)

      expect(live.home_team.score).to be_a(Integer)
      expect(live.away_team.score).to be_a(Integer)
      expect(live).to have_attributes(period: a_value >= 1, period_type: :regulation)
      expect([live.clock_running, live.in_intermission]).to all(be(true).or(be(false)))
      expect(live.clock).to match(/\A\d\d:\d\d\z/)
      expect(live.codes).to eq(period_type: "REG")
    end

    it "leaves period and clock empty for games that haven't started" do
      upcoming = scores.reject(&:live?).reject(&:final?)

      expect(upcoming).not_to be_empty
      expect(upcoming.map(&:state).uniq - %i[scheduled pregame]).to be_empty
      expect(upcoming).to all(have_attributes(period: nil, period_type: nil, clock: nil, codes: {}))
      expect(upcoming.map { |s| s.home_team.score }).to all(be_nil)
    end

    it "round-trips through the processed cache" do
      cache = SportsIngest::Cache::Processed.new(store: SportsIngest::Cache::MemoryStore.new)

      cache.write("nhl/scores/2026-11-23", scores, source: :nhl)

      expect(cache.read("nhl/scores/2026-11-23", model: SportsIngest::NHL::GameScore).models).to eq(scores)
    end
  end

  describe "#on" do
    it "reads a given date" do
      stub_day("2026-11-22", game_json)

      score = scoreboard.on(Date.new(2026, 11, 22)).first

      expect(score).to have_attributes(id: "2026020373", state: :final, period: 3, seconds_remaining: 0,
        clock: "00:00", clock_running: false, in_intermission: false)
      expect(score.game).to have_attributes(date: Date.new(2026, 11, 22), ended_in: :regulation,
        venue: "Madison Square Garden")
      expect([score.away_team.tri_code, score.away_team.score]).to eq(["CAR", 5])
    end

    it "reads a shootout and an intermission" do
      stub_day("2026-11-22",
        game_json("id" => 1, "periodDescriptor" => {"number" => 5, "periodType" => "SO"},
          "gameOutcome" => {"lastPeriodType" => "SO"}),
        game_json("id" => 2, "gameState" => "LIVE", "gameOutcome" => nil,
          "clock" => {"secondsRemaining" => 754, "running" => false, "inIntermission" => true},
          "periodDescriptor" => {"number" => 2, "periodType" => "REG"}))

      shootout, intermission = scoreboard.on("2026-11-22").sort_by(&:id)

      expect(shootout).to have_attributes(period: 5, period_type: :shootout, final?: true)
      expect(intermission).to have_attributes(live?: true, period: 2, in_intermission: true, clock: "12:34")
      expect(intermission.game.ended_in).to be_nil
    end

    it "returns nothing on a day without games" do
      stub_day("2026-07-15")

      expect(scoreboard.on("2026-07-15")).to eq([])
    end

    it "reads an unknown period type as :unknown and keeps the code" do
      stub_day("2026-11-22", game_json("periodDescriptor" => {"number" => 4, "periodType" => "3X3"}))
      SportsIngest::NHL::Game::WARNED.clear

      score = nil
      expect { score = scoreboard.on("2026-11-22").first }.to output(/unknown ended_in code "3X3"/).to_stderr
      expect(score).to have_attributes(period_type: :unknown, codes: {period_type: "3X3"})
    end

    it "raises SourceChangedError for a missing field" do
      stub_day("2026-11-22", game_json.except("homeTeam"))

      expect { scoreboard.on("2026-11-22") }.to raise_error(SportsIngest::SourceChangedError, /2026020373/)
    end

    it "raises SourceChangedError when there's no games list" do
      stub_request(:get, "#{base}/score/2026-11-22").to_return(status: 200, body: "{}")

      expect { scoreboard.on("2026-11-22") }.to raise_error(SportsIngest::SourceChangedError, /games/)
    end

    it "rejects a date that isn't one" do
      expect { scoreboard.on("tomorrow") }.to raise_error(ArgumentError, /YYYY-MM-DD/)
    end
  end

  it "keeps scores fresh for TTL seconds by default" do
    raw = described_class.new.instance_variable_get(:@client).instance_variable_get(:@http)

    expect(raw.send(:ttl)).to eq(described_class::TTL)
  end
end

RSpec.describe SportsIngest::NHL::GameScore do
  let(:game) do
    {id: "1", season: 2026, game_type: :regular, date: "2026-11-23", start_time: "2026-11-24T00:00:00Z",
     state: :live, schedule_state: :ok, home_team: {id: 1, tri_code: "NJD", score: 2},
     away_team: {id: 29, tri_code: "CBJ", score: 0}}
  end

  it "rejects a period below 1 and a negative clock" do
    expect { described_class.new(game: game, period: 0) }.to raise_error(ArgumentError, /period/)
    expect { described_class.new(game: game, seconds_remaining: -1) }.to raise_error(ArgumentError, /seconds_remaining/)
  end

  it "rejects a period type it doesn't know" do
    expect { described_class.new(game: game, period_type: :fourth) }.to raise_error(ArgumentError, /period_type|ended_in/)
  end

  it "round-trips through JSON" do
    score = described_class.new(game: game, period: 1, period_type: "regulation", seconds_remaining: 496,
      clock_running: true, in_intermission: false, codes: {"period_type" => "REG"})

    expect(described_class.from_h(JSON.parse(score.to_json))).to eq(score)
  end
end
