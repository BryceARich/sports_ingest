# frozen_string_literal: true

require "sports_ingest/nhl"

RSpec.describe SportsIngest::NHL::PlayerDetails do
  subject(:details) do
    described_class.new(
      player: {ref: {sport: :hockey, canonical_id: 8_478_402}, first_name: "Connor", last_name: "McDavid",
               position: "C", team: "EDM", sweater_number: 97, shoots_catches: "L", height_inches: 74,
               weight_pounds: 190, birth_date: "1997-01-13", birth_city: "Richmond Hill",
               birth_state_province: "ON", birth_country: "CAN", headshot: nil},
      active: true,
      draft: {year: 2015, team: "EDM", round: 1, pick_in_round: 1, overall_pick: 1},
      career_regular_season: {game_type: :regular, games_played: 820, points: 1278, avg_toi_seconds: 1315},
      seasons: [
        {season: 2014, game_type: "regular", league: "OHL", team_name: "Erie Otters", games_played: 47},
        {season: 2015, game_type: :regular, league: "NHL", team_name: "Edmonton Oilers", games_played: 45},
        {season: 2016, game_type: :playoffs, league: "NHL", team_name: "Edmonton Oilers", games_played: 13}
      ]
    )
  end

  it "builds nested models from hashes and delegates identity to the player" do
    expect(details.player.birth_date).to eq(Date.new(1997, 1, 13))
    expect(details.id).to eq("8478402")
    expect(details.full_name).to eq("Connor McDavid")
    expect(details.seasons.first.game_type).to eq(:regular)
  end

  it "picks out NHL seasons by game type" do
    expect(details.nhl_seasons.map(&:season)).to eq([2015])
    expect(details.nhl_seasons(game_type: :playoffs).map(&:season)).to eq([2016])
    expect(details.seasons.count(&:nhl?)).to eq(2)
    expect(details.career_regular_season).to be_nhl
  end

  it "round-trips through JSON" do
    expect(described_class.from_h(JSON.parse(details.to_json))).to eq(details)
  end

  it "rejects a non-Boolean active" do
    expect { details.with(active: "yes") }.to raise_error(ArgumentError, /active/)
  end

  describe SportsIngest::NHL::StatLine do
    it "rejects an unknown stat or game type" do
      expect { described_class.new(game_type: :regular, hits: 3) }.to raise_error(ArgumentError, /hits/)
      expect { described_class.new(game_type: :exhibition) }.to raise_error(ArgumentError, /game_type/)
    end
  end

  describe SportsIngest::NHL::GameLogEntry do
    subject(:entry) do
      described_class.new(player_id: 8_478_402, game_id: 2_025_020_001, season: 2025, game_type: :regular,
        date: "2025-10-08", team: "EDM", opponent: "CGY", home: false, goals: 1, toi_seconds: 1265)
    end

    it "coerces IDs and the date, and leaves missing stats nil" do
      expect(entry).to have_attributes(player_id: "8478402", game_id: "2025020001", date: Date.new(2025, 10, 8),
        assists: nil, decision: nil)
      expect(entry).to be_road
    end

    it "round-trips through JSON" do
      expect(described_class.from_h(JSON.parse(entry.to_json))).to eq(entry)
    end

    it "rejects a non-Boolean home or a bad date" do
      expect { entry.with(home: "H") }.to raise_error(ArgumentError, /home/)
      expect { entry.with(date: "10/08/2025") }.to raise_error(ArgumentError, /date/)
    end
  end
end
