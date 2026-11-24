# frozen_string_literal: true

require "sports_ingest/nhl"

# The poll interval recommended from a game's state (M2-10, ADR 0025). Offline: each game is built
# in place, one per state in the table.
RSpec.describe SportsIngest::NHL::PollInterval do
  # Builds a GameScore for one state of play.
  build_score = lambda do |state:, ended_in: nil, **fields|
    game = {id: "2026020001", season: 2026, game_type: :regular, date: "2026-11-23", start_time: "2026-11-24T00:00:00Z",
            state: state, schedule_state: :ok, ended_in: ended_in,
            home_team: {id: 1, tri_code: "NJD", score: 2}, away_team: {id: 29, tri_code: "CBJ", score: 0}}
    SportsIngest::NHL::GameScore.new(game: game, **fields)
  end

  # Each row: [description, GameScore, expected phase, expected seconds].
  states = [
    ["scheduled, not started", build_score.call(state: :scheduled), :pre, 60],
    ["in pregame", build_score.call(state: :pregame), :pre, 60],
    ["in regulation", build_score.call(state: :live, period: 2, period_type: :regulation, seconds_remaining: 300), :regulation, 10],
    ["in overtime", build_score.call(state: :live, period: 4, period_type: :overtime, seconds_remaining: 120), :overtime, 10],
    ["in a shootout", build_score.call(state: :live, period: 5, period_type: :shootout), :shootout, 10],
    ["between periods", build_score.call(state: :live, period: 1, period_type: :regulation, in_intermission: true), :intermission, 30],
    ["final in regulation", build_score.call(state: :final, period: 3, period_type: :regulation, seconds_remaining: 0, ended_in: :regulation), :final, nil],
    ["final in a shootout", build_score.call(state: :final, period: 5, period_type: :shootout, ended_in: :shootout), :final, nil],
    ["in a state the gem doesn't know", build_score.call(state: :unknown), :unknown, 60]
  ]

  describe ".for" do
    states.each do |description, game_score, phase, seconds|
      it "is #{seconds.inspect} seconds for a game #{description} (#{phase})" do
        expect(game_score.phase).to eq(phase)
        expect(described_class.for(game_score)).to eq(seconds)
      end
    end

    it "rejects something that isn't a GameScore" do
      expect { described_class.for({phase: :live}) }.to raise_error(ArgumentError, /GameScore/)
    end
  end

  describe ".for_phase" do
    it "gives the same table as .for, for every phase" do
      states.each do |_description, _game_score, phase, seconds|
        expect(described_class.for_phase(phase)).to eq(seconds)
      end
    end

    it "rejects a phase it doesn't know" do
      expect { described_class.for_phase(:warmup) }.to raise_error(ArgumentError, /warmup/)
    end
  end
end
