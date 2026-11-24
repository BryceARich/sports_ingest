# frozen_string_literal: true

require "sports_ingest/nhl"

RSpec.describe SportsIngest::NHL::SeasonStats do
  subject(:stats) { described_class.new(client: client, processed: processed, today: Date.new(2026, 11, 23)) }

  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.raw_cache = :off } }
  let(:http) do
    SportsIngest::HTTP::Client.new(source: :nhl, max_retries: 0, configuration: config,
      rate_limiter: SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}))
  end
  let(:client) { SportsIngest::NHL::Client.new(http: http) }
  let(:processed) { SportsIngest::Cache::Processed.new(store: SportsIngest::Cache::MemoryStore.new) }
  let(:url) { "https://api.nhle.com/stats/rest/en/skater/summary" }

  def skater(id, season: 20_262_027, **extra)
    {"playerId" => id, "skaterFullName" => "Player #{id}", "positionCode" => "C", "teamAbbrevs" => "TOR",
     "seasonId" => season, "gamesPlayed" => 20, "goals" => 5, "assists" => 7, "points" => 12,
     "penaltyMinutes" => 4, "ppGoals" => 1, "shootingPct" => 0.1, "timeOnIcePerGame" => 1061.6}.merge(extra)
  end

  def stub_page(season_id, start, rows, total, game_type: 2)
    stub_request(:get, url).with(query: hash_including(
      "cayenneExp" => "seasonId=#{season_id} and gameTypeId=#{game_type}", "start" => start.to_s, "limit" => "100"
    )).to_return(headers: {"Content-Type" => "application/json"}, body: {data: rows, total: total}.to_json)
  end

  # Playoff tables keep the recording small: ~25-28 goalies a season, one page each.
  context "with recorded playoff goalie tables for 2022-23 to 2026-27",
    vcr: {cassette_name: "nhl/stats_goalie_summary_2022_to_2026_playoffs", allow_playback_repeats: true} do
    it "loads last: 5 and last: 3 with NHL ids, one row per goalie per season" do
      five = stats.goalies(last: 5, game_type: :playoffs)
      three = stats.goalies(last: 3, game_type: :playoffs)

      # The 2026-27 playoffs haven't started, so the current season comes back empty.
      expect(five.map(&:season).uniq).to eq([2022, 2023, 2024, 2025])
      expect(three.map(&:season).uniq).to eq([2024, 2025])
      expect(three).to eq(five.select { it.season >= 2024 })
      expect(five).to all(have_attributes(position: "G", game_type: :playoffs, player_id: match(/\A\d{7}\z/)))
      expect(five.group_by(&:season).values).to all(satisfy { |rows| rows.map(&:player_id).uniq.size == rows.size })

      line = five.select { it.season == 2024 }.max_by { it.stats.games_played }.stats
      expect(line).to have_attributes(league: "NHL", team_name: nil, shots: nil)
      expect(line.wins + line.losses + line.ot_losses).to be <= line.games_played
      expect(line.save_pct).to be_between(0.85, 0.95)
      expect(line.toi_seconds).to be > line.games_played * 50 * 60
    end
  end

  context "with a recorded skater row", vcr: {cassette_name: "nhl/stats_skater_summary_limit_1"} do
    it "parses a real skater/summary row" do
      payload = client.stats_json("skater/summary", params: {limit: 1, cayenneExp: "seasonId=20252026 and gameTypeId=2"})
      row = stats.parse_page(payload, kind: :skaters, game_type: :regular).first

      expect(row).to have_attributes(player_id: match(/\A\d+\z/), season: 2025, game_type: :regular, goalie?: false)
      expect(row.teams).not_to be_empty
      expect(row.stats.points).to eq(row.stats.goals + row.stats.assists)
      expect(row.stats.avg_toi_seconds).to be_between(5 * 60, 30 * 60)
      expect(row.stats.wins).to be_nil
    end
  end

  it "reads last: 3 by default, paging each season until its total" do
    stub_page(20_242_025, 0, [skater(2, season: 20_242_025)], 1)
    stub_page(20_252_026, 0, [skater(2, season: 20_252_026)], 1)
    stub_page(20_262_027, 0, (1..100).map { skater(it + 100) }, 101)
    stub_page(20_262_027, 100, [skater(1)], 101)

    rows = stats.skaters
    expect(rows.map(&:season).tally).to eq(2024 => 1, 2025 => 1, 2026 => 101)
    expect(rows.select { it.season == 2026 }.first.player_id).to eq("1")
  end

  it "maps skater fields, splits traded players' teams, and rounds time on ice" do
    stub_page(20_262_027, 0, [skater(8_478_402, "teamAbbrevs" => "TOR,EDM")], 1)

    row = stats.skaters(seasons: [2026]).first
    expect(row).to have_attributes(player_id: "8478402", full_name: "Player 8478402", position: "C",
      teams: %w[TOR EDM], season: 2026)
    expect(row.stats).to have_attributes(pim: 4, power_play_goals: 1, shooting_pct: 0.1, avg_toi_seconds: 1062)
  end

  it "asks for playoffs with game type 3" do
    stub_page(20_262_027, 0, [], 0, game_type: 3)
    expect(stats.skaters(last: 1, game_type: :playoffs)).to eq([])
  end

  it "saves each season to the processed cache" do
    stub_page(20_262_027, 0, [skater(1)], 1)
    stats.skaters(last: 1)

    entry = processed.read("nhl/season_stats/skaters/20262027/regular", model: SportsIngest::NHL::SeasonTotal)
    expect(entry.models.map(&:player_id)).to eq(["1"])
  end

  it "stops on an empty page even if the total says there's more" do
    stub_page(20_262_027, 0, [], 50)
    expect(stats.skaters(last: 1)).to eq([])
  end

  it "rejects bad keywords before any request" do
    expect { stats.skaters(game_type: :preseason) }.to raise_error(ArgumentError, /game_type/)
    expect { stats.goalies(seasons: [2025], last: 2) }.to raise_error(ArgumentError, /not both/)
  end

  it "raises SourceChangedError for a payload of the wrong shape" do
    stub_request(:get, url).with(query: hash_including({}))
      .to_return(headers: {"Content-Type" => "application/json"}, body: {data: [{"playerId" => "x"}], total: 1}.to_json)
    expect { stats.skaters(last: 1) }.to raise_error(SportsIngest::SourceChangedError, /SeasonTotal/)
  end
end
