# frozen_string_literal: true

require "json"
require "sports_ingest/nhl"

# Live game state on NHL::GameScore (M2-04, ADR 0019): one recorded fixture per state where the NHL
# had one, stubs for the live overtime and shootout states that are hard to catch.
RSpec.describe "NHL live game state" do
  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.raw_cache = :off } }
  let(:http) do
    SportsIngest::HTTP::Client.new(source: :nhl, max_retries: 0, configuration: config,
      rate_limiter: SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}))
  end
  let(:client) { SportsIngest::NHL::Client.new(http: http) }
  let(:scoreboard) { SportsIngest::NHL::Scoreboard.new(client: client) }

  def by_id(scores)
    scores.to_h { |score| [score.id, score] }
  end

  describe "before the puck drops", vcr: {cassette_name: "nhl/score_now_2026_11_23"} do
    it "reads as :pre with no shots or situation" do
      upcoming = scoreboard.on.reject(&:live?)

      expect(upcoming).not_to be_empty
      expect(upcoming).to all(have_attributes(phase: :pre, home_shots: nil, away_shots: nil, situation: nil,
        power_play: nil))
    end

    it "gives a game in regulation its shots on goal" do
      live = by_id(scoreboard.on).fetch("2026020378")

      expect(live).to have_attributes(phase: :regulation, home_shots: 7, away_shots: 7, situation: nil)
    end
  end

  describe "a power play and an intermission", vcr: {cassette_name: "nhl/score_now_2026_11_23_late"} do
    subject(:scores) { by_id(scoreboard.on) }

    it "reads the team on the power play, the strength and the penalty clock" do
      score = scores.fetch("2026020383")

      expect(score).to have_attributes(phase: :regulation, period: 2, power_play: :away, home_shots: 10,
        away_shots: 8)
      expect(score.situation).to have_attributes(code: "1541", away_skaters: 5, home_skaters: 4,
        home_goalie_in: true, away_goalie_in: true, seconds_remaining: 240, clock: "04:00",
        away_descriptions: ["PP"], home_descriptions: [], empty_net: [])
      expect(score.situation.strength(:away)).to eq("5v4")
      expect(score.situation.strength(:home)).to eq("4v5")
    end

    it "reads a game between periods as :intermission" do
      score = scores.fetch("2026020384")

      expect(score).to have_attributes(phase: :intermission, live?: true, in_intermission: true, period: 1)
      expect([score.home_shots, score.away_shots]).to all(be_a(Integer))
    end

    it "reads finished games as :final with their shots" do
      finals = scores.values.select(&:final?)

      expect(finals).not_to be_empty
      expect(finals).to all(have_attributes(phase: :final, situation: nil))
      expect(finals.flat_map { |s| [s.home_shots, s.away_shots] }).to all(be_a(Integer))
    end

    it "round-trips through the processed cache" do
      cache = SportsIngest::Cache::Processed.new(store: SportsIngest::Cache::MemoryStore.new)
      list = scores.values

      cache.write("nhl/scores/now", list, source: :nhl)

      expect(cache.read("nhl/scores/now", model: SportsIngest::NHL::GameScore).models).to eq(list)
    end
  end

  describe "games decided in overtime and a shootout", vcr: {cassette_name: "nhl/score_2026_11_21"} do
    subject(:scores) { by_id(scoreboard.on("2026-11-21")) }

    it "reads an overtime final, clock stopped where the winner went in" do
      score = scores.fetch("2026020360")

      expect(score).to have_attributes(phase: :final, period: 4, period_type: :overtime, seconds_remaining: 15)
      expect(score.game.ended_in).to eq(:overtime)
    end

    it "reads a shootout final" do
      score = scores.fetch("2026020369")

      expect(score).to have_attributes(phase: :final, period: 5, period_type: :shootout)
      expect(score.game.ended_in).to eq(:shootout)
    end

    it "reads a regulation final" do
      regulation = scores.values.select { |s| s.game.ended_in == :regulation }

      expect(regulation).not_to be_empty
      expect(regulation).to all(have_attributes(phase: :final, period: 3, period_type: :regulation))
    end
  end

  describe "states stubbed from the recorded shape" do
    let(:base) { "https://api-web.nhle.com/v1" }

    def live_game(id, number, type, situation: nil)
      {"id" => id, "season" => 20262027, "gameType" => 2, "gameDate" => "2026-11-23",
       "startTimeUTC" => "2026-11-24T03:00:00Z", "gameState" => "LIVE", "gameScheduleState" => "OK",
       "homeTeam" => {"id" => 28, "abbrev" => "SJS", "score" => 2, "sog" => 30},
       "awayTeam" => {"id" => 30, "abbrev" => "MIN", "score" => 2, "sog" => 33},
       "clock" => {"secondsRemaining" => 187, "running" => true, "inIntermission" => false},
       "periodDescriptor" => {"number" => number, "periodType" => type}, "situation" => situation}.compact
    end

    def scores_for(*games)
      stub_request(:get, "#{base}/score/2026-11-23")
        .to_return(status: 200, body: JSON.generate({"games" => games}))
      by_id(scoreboard.on("2026-11-23"))
    end

    it "reads overtime and shootout in progress" do
      scores = scores_for(live_game(1, 4, "OT"), live_game(2, 5, "SO"))

      expect(scores.fetch("1").phase).to eq(:overtime)
      expect(scores.fetch("2").phase).to eq(:shootout)
    end

    it "doesn't call a pulled goalie's extra attacker a power play" do
      pulled = {"homeTeam" => {"abbrev" => "SJS", "situationDescriptions" => ["EN"], "strength" => 6},
                "awayTeam" => {"abbrev" => "MIN", "strength" => 5}, "situationCode" => "1560"}

      score = scores_for(live_game(1, 3, "REG", situation: pulled)).fetch("1")

      expect(score.power_play).to be_nil
      expect(score.situation).to have_attributes(empty_net: [:home], seconds_remaining: nil, clock: nil,
        home_descriptions: ["EN"])
      expect(score.situation.strength(:home)).to eq("6v5")
    end

    it "reads a five-on-three for the home side" do
      five_on_three = {"homeTeam" => {"abbrev" => "SJS", "situationDescriptions" => ["PP"], "strength" => 5},
                       "awayTeam" => {"abbrev" => "MIN", "strength" => 3}, "situationCode" => "1351",
                       "secondsRemaining" => 61}

      score = scores_for(live_game(1, 2, "REG", situation: five_on_three)).fetch("1")

      expect(score.power_play).to eq(:home)
      expect(score.situation.clock).to eq("01:01")
    end

    it "reads an unknown period type in progress as :unknown" do
      SportsIngest::NHL::Game::WARNED << [:ended_in, "3X3"]

      expect(scores_for(live_game(1, 4, "3X3")).fetch("1").phase).to eq(:unknown)
    end

    it "raises SourceChangedError for a situation without a code" do
      broken = {"homeTeam" => {"abbrev" => "SJS"}, "awayTeam" => {"abbrev" => "MIN"}}

      expect { scores_for(live_game(1, 2, "REG", situation: broken)) }
        .to raise_error(SportsIngest::SourceChangedError, /situationCode/)
    end
  end
end

RSpec.describe SportsIngest::NHL::Situation do
  it "decodes the situation code: away goalie, away skaters, home skaters, home goalie" do
    expect(described_class.new(code: "1451")).to have_attributes(away_goalie_in: true, away_skaters: 4,
      home_skaters: 5, home_goalie_in: true, power_play: :home)
  end

  it "reads even strength as no power play" do
    expect(described_class.new(code: "1441").power_play).to be_nil
  end

  it "rejects a code that isn't four digits or has a goalie digit above 1" do
    ["145", "2451", 1451, "1a51"].each do |code|
      expect { described_class.new(code: code) }.to raise_error(ArgumentError, /situationCode/)
    end
  end

  it "rejects counts that disagree with the code" do
    expect { described_class.new(code: "1451", home_skaters: 4) }.to raise_error(ArgumentError, /home_skaters/)
  end

  it "rejects a negative clock and descriptions that aren't strings" do
    expect { described_class.new(code: "1451", seconds_remaining: -1) }.to raise_error(ArgumentError, /seconds/)
    expect { described_class.new(code: "1451", home_descriptions: "PP") }.to raise_error(ArgumentError, /descriptions/)
  end

  it "rejects a side that isn't home or away" do
    expect { described_class.new(code: "1451").strength(:left) }.to raise_error(ArgumentError, /side/)
  end

  it "round-trips through JSON inside a GameScore" do
    game = {id: "1", season: 2026, game_type: :regular, date: "2026-11-23", start_time: "2026-11-24T00:00:00Z",
            state: :live, schedule_state: :ok, home_team: {id: 1, tri_code: "NJD", score: 2},
            away_team: {id: 29, tri_code: "CBJ", score: 0}}
    score = SportsIngest::NHL::GameScore.new(game: game, period: 2, period_type: :regulation, home_shots: 12,
      away_shots: 9, situation: {code: "0651", away_descriptions: ["EN"]})

    expect(SportsIngest::NHL::GameScore.from_h(JSON.parse(score.to_json))).to eq(score)
    expect(score.situation.empty_net).to eq([:away])
  end

  it "rejects negative shots" do
    expect { SportsIngest::NHL::GameScore.new(game: nil, home_shots: -1) }.to raise_error(ArgumentError, /home_shots/)
  end
end
