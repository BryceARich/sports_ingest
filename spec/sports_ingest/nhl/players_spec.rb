# frozen_string_literal: true

require "sports_ingest/nhl"

RSpec.describe SportsIngest::NHL::Players do
  subject(:players) { described_class.new(client: client, processed: processed) }

  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.raw_cache = :off } }
  let(:http) do
    SportsIngest::HTTP::Client.new(source: :nhl, max_retries: 0, configuration: config,
      rate_limiter: SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}))
  end
  let(:client) { SportsIngest::NHL::Client.new(http: http) }
  let(:processed) { SportsIngest::Cache::Processed.new(store: SportsIngest::Cache::MemoryStore.new) }
  let(:base) { "https://api-web.nhle.com/v1/player" }
  let(:json) { {"Content-Type" => "application/json"} }

  def stub_player(path, body, status: 200)
    stub_request(:get, "#{base}/#{path}").to_return(status: status, headers: json, body: body.to_json)
  end

  def landing(**extra)
    {"playerId" => 8_478_402, "isActive" => true, "currentTeamAbbrev" => "EDM",
     "firstName" => {"default" => "Connor"}, "lastName" => {"default" => "McDavid"}, "position" => "C",
     "birthDate" => "1997-01-13", "shootsCatches" => "L", "seasonTotals" => []}.merge(extra)
  end

  def log_row(**extra)
    {"gameId" => 2_025_020_001, "teamAbbrev" => "EDM", "homeRoadFlag" => "H", "gameDate" => "2025-10-08",
     "goals" => 1, "assists" => 1, "points" => 2, "toi" => "21:05", "opponentAbbrev" => "CGY"}.merge(extra)
  end

  context "with McDavid's recorded landing", vcr: {cassette_name: "nhl/player_8478402_landing"} do
    let(:details) { players.fetch(8_478_402) }

    it "parses his bio, including birth date and shooting hand" do
      expect(details.player).to have_attributes(id: "8478402", full_name: "Connor McDavid", position: "C",
        team: "EDM", birth_date: Date.new(1997, 1, 13), shoots_catches: "L", birth_country: "CAN")
      expect(details).to be_active
    end

    it "parses his draft" do
      expect(details.draft).to have_attributes(year: 2015, team: "EDM", round: 1, overall_pick: 1)
    end

    it "parses career totals for the regular season and playoffs" do
      regular = details.career_regular_season
      expect(regular).to have_attributes(season: nil, game_type: :regular, league: nil)
      expect(regular.points).to eq(regular.goals + regular.assists)
      expect(regular.avg_toi_seconds).to be_between(18 * 60, 25 * 60)
      expect(details.career_playoffs.game_type).to eq(:playoffs)
    end

    it "lists season totals in every league, with his NHL seasons from 2015 on" do
      expect(details.seasons.map(&:league)).to include("NHL", "OHL")
      nhl = details.nhl_seasons
      expect(nhl.first).to have_attributes(season: 2015, team_name: "Edmonton Oilers", game_type: :regular)
      expect(nhl.sum(&:games_played)).to eq(details.career_regular_season.games_played)
      expect(details.nhl_seasons(game_type: :playoffs)).to all(have_attributes(game_type: :playoffs))
    end

    it "saves the details to the processed cache" do
      details
      entry = processed.read("nhl/players/8478402", model: SportsIngest::NHL::PlayerDetails)

      expect(entry.models).to eq([details])
    end
  end

  context "with a goalie's recorded landing", vcr: {cassette_name: "nhl/player_8479361_landing"} do
    it "fills the goalie stats and leaves skater-only ones nil" do
      career = players.fetch("8479361").career_regular_season

      expect(career.save_pct).to be_between(0.8, 1.0)
      expect(career.toi_seconds).to be > 0
      expect(career).to have_attributes(shots: nil, avg_toi_seconds: nil)
      expect(career.wins + career.losses + career.ot_losses).to be <= career.games_played
    end
  end

  context "with McDavid's recorded 2025-26 game log", vcr: {cassette_name: "nhl/player_8478402_game_log_20252026_2"} do
    let(:log) { players.game_log(8_478_402, season: 2025) }

    it "returns one entry per game, oldest first" do
      expect(log.size).to eq(82)
      expect(log.map(&:date)).to eq(log.map(&:date).sort)
      expect(log).to all(have_attributes(player_id: "8478402", season: 2025, game_type: :regular, team: "EDM"))
      expect(log.first.date).to be >= Date.new(2025, 10, 1)
    end

    it "parses each line" do
      expect(log.sum(&:points)).to eq(log.sum(&:goals) + log.sum(&:assists))
      expect(log.map(&:toi_seconds)).to all(be > 0)
      expect(log.map(&:home).tally.keys).to contain_exactly(true, false)
      expect(log.map(&:decision).uniq).to eq([nil])
    end

    it "saves the log to the processed cache" do
      log
      entry = processed.read("nhl/game_logs/8478402/20252026/regular", model: SportsIngest::NHL::GameLogEntry)

      expect(entry.models).to eq(log)
    end
  end

  context "with a goalie's recorded 2025-26 game log", vcr: {cassette_name: "nhl/player_8479361_game_log_20252026_2"} do
    it "parses decisions and saves" do
      log = players.game_log(8_479_361, season: 2025)

      expect(log.map(&:decision).compact).to all(match(/\A[WLO]\z/))
      expect(log.map(&:save_pct).compact).not_to be_empty
      expect(log.map(&:shots)).to all(be_nil)
    end
  end

  describe "#fetch" do
    it "keeps optional fields nil for an undrafted, retired player" do
      stub_player("8478402/landing", landing("isActive" => false, "currentTeamAbbrev" => nil))

      details = players.fetch("8478402")
      expect(details).to have_attributes(active: false, draft: nil, career_regular_season: nil, seasons: [])
      expect(details.player.team).to be_nil
    end

    it "raises NotFound for an unknown player" do
      stub_request(:get, "#{base}/1/landing").to_return(status: 404, body: "<html>Not Found</html>")

      expect { players.fetch(1) }.to raise_error(SportsIngest::NotFound)
    end

    it "rejects an ID that isn't all digits" do
      expect { players.fetch("../roster") }.to raise_error(ArgumentError, /digits/)
      expect { players.fetch(nil) }.to raise_error(ArgumentError, /digits/)
    end

    it "works without a processed cache" do
      stub_player("8478402/landing", landing)

      expect(described_class.new(client: client, processed: nil).fetch(8_478_402).id).to eq("8478402")
    end
  end

  describe "#game_log" do
    it "asks for the playoffs" do
      stub_player("8478402/game-log/20242025/3", {"seasonId" => 20_242_025, "gameTypeId" => 3, "gameLog" => [log_row]})

      expect(players.game_log(8_478_402, season: 2024, game_type: :playoffs).first.game_type).to eq(:playoffs)
      expect(processed.read("nhl/game_logs/8478402/20242025/playoffs", model: SportsIngest::NHL::GameLogEntry)).not_to be_nil
    end

    it "returns an empty log for a season without games" do
      stub_player("8478402/game-log/20082009/2", {"seasonId" => 20_082_009, "gameTypeId" => 2, "playerStatsSeasons" => []})

      expect(players.game_log(8_478_402, season: 2008)).to eq([])
    end

    it "reads the current log and saves it under the season it turned out to be" do
      stub_player("8478402/game-log/now", {"seasonId" => 20_262_027, "gameTypeId" => 2,
                                            "gameLog" => [log_row("gameDate" => "2026-10-09"), log_row("gameDate" => "2026-10-07")]})

      log = players.game_log(8_478_402)
      expect(log.map(&:date)).to eq([Date.new(2026, 10, 7), Date.new(2026, 10, 9)])
      expect(processed.read("nhl/game_logs/8478402/20262027/regular", model: SportsIngest::NHL::GameLogEntry).models).to eq(log)
    end

    it "rejects a game type without a season, or an unknown one" do
      expect { players.game_log(8_478_402, game_type: :playoffs) }.to raise_error(ArgumentError, /season/)
      expect { players.game_log(8_478_402, season: 2025, game_type: :preseason) }.to raise_error(ArgumentError, /game_type/)
    end
  end

  describe "#parse_game_log" do
    it "reads a goalie's penaltyMins as pim" do
      payload = {"seasonId" => 20_262_027, "gameTypeId" => 2,
                 "gameLog" => [log_row("penaltyMins" => 2, "decision" => "W", "savePctg" => 0.9).except("goals", "assists", "points")]}

      expect(players.parse_game_log(payload, player_id: "1").first).to have_attributes(pim: 2, decision: "W", goals: nil)
    end

    it "raises SourceChangedError for a bad row" do
      payload = {"seasonId" => 20_262_027, "gameTypeId" => 2, "gameLog" => [log_row("homeRoadFlag" => "N")]}

      expect { players.parse_game_log(payload, player_id: "1") }.to raise_error(SportsIngest::SourceChangedError, /homeRoadFlag/)
    end

    it "raises SourceChangedError for a time on ice it can't read" do
      payload = {"seasonId" => 20_262_027, "gameTypeId" => 2, "gameLog" => [log_row("toi" => "21m")]}

      expect { players.parse_game_log(payload, player_id: "1") }.to raise_error(SportsIngest::SourceChangedError, /time on ice/)
    end
  end

  describe "#parse_landing" do
    it "raises SourceChangedError for a player the model rejects" do
      expect { players.parse_landing(landing("position" => "F")) }
        .to raise_error(SportsIngest::SourceChangedError, /8478402.*position/)
    end

    it "raises SourceChangedError without seasonTotals" do
      expect { players.parse_landing(landing.except("seasonTotals")) }
        .to raise_error(SportsIngest::SourceChangedError, /seasonTotals/)
    end
  end

  describe "SportsIngest::NHL.player and .game_log" do
    it "fetch through a new Players" do
      instance = instance_double(described_class, fetch: :details, game_log: [])
      allow(described_class).to receive(:new).and_return(instance)

      expect(SportsIngest::NHL.player(8_478_402)).to eq(:details)
      expect(SportsIngest::NHL.game_log(8_478_402, season: 2025)).to eq([])
      expect(instance).to have_received(:game_log).with(8_478_402, season: 2025, game_type: nil)
    end
  end
end
