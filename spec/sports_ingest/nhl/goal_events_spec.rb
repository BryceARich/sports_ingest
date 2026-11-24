# frozen_string_literal: true

require "sports_ingest/nhl"

# Goal events from the play-by-play (M2-05, ADR 0020). CBJ at NJD on 2026-11-22 (game 2026020378), a
# finished game with five goals, is recorded; the "poll before the last goal" snapshot is that same
# recording cut off before the last goal's sortOrder, which is what a poll at that moment would have seen.
RSpec.describe SportsIngest::NHL::GoalEvents do
  subject(:goals) { described_class.new(client: client) }

  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.raw_cache = :off } }
  let(:http) do
    SportsIngest::HTTP::Client.new(source: :nhl, max_retries: 0, configuration: config,
      rate_limiter: SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}))
  end
  let(:client) { SportsIngest::NHL::Client.new(http: http) }

  describe "a finished game", vcr: {cassette_name: "nhl/play_by_play_2026020378"} do
    it "lists every goal in the NHL's order, with scorer, assists, strength and score" do
      all = goals.fetch(2026020378)

      expect(all.size).to eq(5)
      expect(all.first).to have_attributes(event_id: 105, game_id: 2026020378, period: 1, time_in_period: "04:59",
        time_remaining: "15:01", side: :home, team_id: 1, scorer_id: 8478414, assist_ids: [8481559, 8477015],
        strength: "EV", shot_type: "wrist", home_score: 1, away_score: 0)
      expect(all[1].assist_ids).to eq([8483695])
      expect(all[2]).to have_attributes(side: :away, team_id: 29, assist_ids: [8478460], away_score: 1)
    end

    it "reads a goal scored a player down as short-handed from the goal's own situation" do
      last = goals.fetch(2026020378).last

      expect(last).to have_attributes(event_id: 780, period: 2, time_in_period: "19:46", side: :away,
        scorer_id: 8482451, assist_ids: [8476923, 8485469], strength: "SH", home_score: 3, away_score: 2)
      expect(last.situation).to have_attributes(code: "1451", away_skaters: 4, home_skaters: 5)
    end
  end

  describe "two sequential polls", vcr: {cassette_name: "nhl/play_by_play_2026020378"} do
    it "yields exactly the new goal between them" do
      payload = client.get_json("gamecenter/2026020378/play-by-play")
      last_goal = payload.fetch("plays").select { |play| play["typeDescKey"] == "goal" }.last
      before_last = payload.merge("plays" => payload.fetch("plays").select { |play| play["sortOrder"] < last_goal["sortOrder"] })

      earlier = described_class.parse(before_last)
      later = described_class.parse(payload)
      new_goals = SportsIngest::NHL.new_goals(previous: earlier, current: later)

      expect(earlier.size).to eq(4)
      expect(new_goals.map(&:event_id)).to eq([780])
      expect(new_goals.first.scorer_id).to eq(8482451)
    end

    it "reports nothing new when nothing has happened since the last poll, and everything on the first" do
      later = described_class.parse(client.get_json("gamecenter/2026020378/play-by-play"))

      expect(SportsIngest::NHL.new_goals(previous: later, current: later)).to eq([])
      expect(SportsIngest::NHL.new_goals(previous: [], current: later).size).to eq(5)
    end
  end

  describe "parsing" do
    def play(type: "goal", event_id: 1, code: "1551", owner: 1, period_type: "REG", extra: {})
      details = {"eventOwnerTeamId" => owner, "scoringPlayerId" => 99, "assist1PlayerId" => 98,
                 "homeScore" => 1, "awayScore" => 0}.merge(extra)
      {"eventId" => event_id, "typeDescKey" => type, "sortOrder" => event_id, "situationCode" => code,
       "periodDescriptor" => {"number" => 1, "periodType" => period_type}, "timeInPeriod" => "01:00",
       "timeRemaining" => "19:00", "details" => details}
    end

    def payload(*plays)
      {"id" => 2026020001, "homeTeam" => {"id" => 1}, "awayTeam" => {"id" => 29}, "plays" => plays}
    end

    it "reads a power-play goal as PP for the side that scored" do
      goal = described_class.parse(payload(play(code: "1451"))).first # home 5 skaters vs away 4, both goalies in

      expect(goal).to have_attributes(side: :home, strength: "PP")
    end

    it "reads a goal against an empty net as EN, whatever the skater count" do
      goal = described_class.parse(payload(play(code: "0551", owner: 1))).first # away goalie out

      expect(goal).to have_attributes(strength: "EN", assist_ids: [98])
    end

    it "leaves shootout attempts out" do
      expect(described_class.parse(payload(play(period_type: "SO", code: "1010")))).to eq([])
    end

    it "leaves out plays that aren't goals" do
      expect(described_class.parse(payload(play(type: "shot-on-goal")))).to eq([])
    end

    it "raises SourceChangedError when a goal's details are missing" do
      broken = play(extra: {})
      broken["details"].delete("scoringPlayerId")

      expect { described_class.parse(payload(broken)) }
        .to raise_error(SportsIngest::SourceChangedError, /2026020001/)
    end

    it "rejects a game ID that isn't all digits without asking the NHL" do
      expect { goals.fetch("2026-02") }.to raise_error(ArgumentError, /all digits/)
    end

    it "rejects a list that isn't an array of goals in the diff helper" do
      expect { SportsIngest::NHL.new_goals(previous: nil, current: []) }.to raise_error(ArgumentError)
    end
  end
end
