# frozen_string_literal: true

require "sports_ingest/nhl"

RSpec.describe SportsIngest::NHL::Game do
  let(:fields) do
    {id: 2026020378, season: 2026, game_type: :regular, date: "2026-11-23", start_time: "2026-11-24T00:00:00Z",
     state: :scheduled, schedule_state: :ok, venue: "Prudential Center",
     home_team: {id: 1, tri_code: "NJD"}, away_team: {id: 29, tri_code: "CBJ"}}
  end

  it "coerces IDs, dates, times and nested teams" do
    game = described_class.new(**fields)

    expect(game).to have_attributes(id: "2026020378", date: Date.new(2026, 11, 23),
      start_time: Time.utc(2026, 11, 24), ended_in: nil, neutral_site: false)
    expect(game.home_team).to eq(SportsIngest::NHL::GameTeam.new(id: "1", tri_code: "NJD"))
    expect(game.home_team.team.name).to eq("New Jersey Devils")
    expect(game).to be_frozen
  end

  it "round-trips through JSON" do
    game = described_class.new(**fields, state: "final", ended_in: "overtime",
      codes: {"state" => "OFF", :game_type => 2, :ended_in => "OT"})

    expect(described_class.from_h(JSON.parse(game.to_json))).to eq(game)
  end

  it "answers final?, live? and involves?" do
    game = described_class.new(**fields, state: :live)

    expect(game).to be_live
    expect(game).not_to be_final
    expect(game.involves?(SportsIngest::Teams.fetch("NJD"))).to be(true)
    expect(game.involves?(29)).to be(true)
    expect(game.involves?("10")).to be(false)
  end

  it "maps NHL codes, with a fallback for unknown ones" do
    expect(described_class.from_code(:state, "CRIT")).to eq(:live)
    expect(described_class.from_code(:state, "WARP")).to eq(:unknown)
    expect(described_class.from_code(:game_type, 9)).to eq(:other)
    expect(described_class.from_code(:ended_in, nil)).to be_nil
    expect(described_class.known_code?(:schedule_state, "PPD")).to be(true)
    expect(described_class.new(**fields, state: :unknown, game_type: :other)).to have_attributes(state: :unknown)
  end

  it "rejects values outside the allowed sets" do
    expect { described_class.new(**fields, codes: {clock: "12:00"}) }.to raise_error(ArgumentError, /no field/)
    expect { described_class.new(**fields, codes: {state: nil}) }.to raise_error(ArgumentError, /String or Integer/)
    expect { described_class.new(**fields, state: :paused) }.to raise_error(ArgumentError, /state must be one of/)
    expect { described_class.new(**fields, game_type: 2) }.to raise_error(ArgumentError, /game_type/)
    expect { described_class.new(**fields, season: "2026") }.to raise_error(ArgumentError, /season/)
    expect { described_class.new(**fields, date: "2026-13-01") }.to raise_error(ArgumentError, /date/)
    expect { described_class.new(**fields, neutral_site: nil) }.to raise_error(ArgumentError, /neutral_site/)
    expect { described_class.new(**fields, home_team: {id: 1, tri_code: "NJD", score: -1}) }
      .to raise_error(ArgumentError, /score/)
  end
end
