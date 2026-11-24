# frozen_string_literal: true

require "sports_ingest/nflverse"
require "tmpdir"

RSpec.describe SportsIngest::Nflverse::PlayerStats do
  subject(:stats) { described_class.new(downloader: downloader, processed: processed, today: Date.new(2026, 11, 24)) }

  let(:base) { "https://github.com/nflverse/nflverse-data/releases/download/stats_player" }
  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.ttls = {nflverse: 0} } }
  let(:client) do
    SportsIngest::HTTP::Client.new(source: :nflverse, max_retries: 0, configuration: config,
      rate_limiter: SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}))
  end
  let(:timestamps) do
    SportsIngest::Cache::Raw.new(client: client, store: SportsIngest::Cache::MemoryStore.new, ttl: 0,
      configuration: config)
  end
  let(:dir) { Pathname.new(Dir.mktmpdir("nflverse")) }
  let(:downloader) do
    SportsIngest::Nflverse::ReleaseDownloader.new(client: client, timestamps: timestamps, dir: dir,
      configuration: config, clock: -> { Time.utc(2026, 11, 24, 12) })
  end
  let(:processed) { SportsIngest::Cache::Processed.new(store: SportsIngest::Cache::MemoryStore.new) }

  after { FileUtils.rm_rf(dir) }

  def fixture(name)
    File.read(File.expand_path("../../fixtures/nflverse/#{name}", __dir__))
  end

  def publish(file, body)
    stub_request(:get, "#{base}/#{file}").to_return(status: 200, body: body, headers: {"Content-Type" => "text/csv"})
  end

  before do
    stub_request(:get, "#{base}/timestamp.json").to_return(status: 200,
      body: JSON.generate("last_updated" => "2026-11-22 05:12:43 EST"), headers: {"Content-Type" => "application/json"})
  end

  describe "#weekly" do
    before { publish("stats_player_week_2025.csv", fixture("stats_player_week_2025.csv")) }

    it "returns one model per player per game, ordered by week then player" do
      rows = stats.weekly(seasons: [2025])

      expect(rows).to all(be_a(SportsIngest::Nflverse::PlayerWeekStats))
      expect(rows.map { [it.week, it.player_id] }).to eq([[1, "00-0000001"], [1, "00-0000002"], [2, "00-0000002"]])
    end

    it "maps identity and game fields, and keeps numeric stats as Integers and Floats" do
      qb = stats.weekly(seasons: [2025]).first

      expect(qb).to have_attributes(player_id: "00-0000001", name: "Example Quarterback", position: "QB",
        team: "KC", season: 2025, season_type: "REG", week: 1, opponent: "BAL")
      expect(qb.stats).to include("passing_yards" => 245, "passing_epa" => 0.15, "fantasy_points_ppr" => 21.4)
    end

    it "leaves out NA and blank stat cells and identity columns" do
      receiver = stats.weekly(seasons: [2025])[1]

      expect(receiver.stats).not_to have_key("passing_epa")
      expect(receiver.stats.keys).not_to include("player_id", "recent_team", "week", "opponent_team")
      expect(receiver.stats).to include("receiving_yards" => 88, "receiving_tds" => 1)
    end

    it "reads the last N seasons, ending at the current one, when given last:" do
      publish("stats_player_week_2024.csv", fixture("stats_player_week_2025.csv"))
      publish("stats_player_week_2026.csv", fixture("stats_player_week_2025.csv"))

      rows = stats.weekly(last: 3)

      expect(rows.map(&:season).uniq).to eq([2024, 2025, 2026])
    end

    it "saves each season to the processed cache" do
      rows = stats.weekly(seasons: [2025])
      entry = processed.read("nflverse/player_stats/weekly/2025", model: SportsIngest::Nflverse::PlayerWeekStats)

      expect(entry).to have_attributes(source: :nflverse, models: rows)
    end

    it "raises SourceChangedError when the file has no week column" do
      publish("stats_player_week_2025.csv", "player_id,player_display_name\n00-1,Someone\n")

      expect { stats.weekly(seasons: [2025]) }.to raise_error(SportsIngest::SourceChangedError, /week/)
    end
  end

  describe "#season" do
    before { publish("stats_player_reg_2025.csv", fixture("stats_player_reg_2025.csv")) }

    it "returns one regular-season model per player, with totals" do
      rows = stats.season(seasons: [2025])

      expect(rows).to all(be_a(SportsIngest::Nflverse::PlayerSeasonStats))
      expect(rows.map(&:player_id)).to eq(%w[00-0000001 00-0000002])
      expect(rows.first).to have_attributes(name: "Example Quarterback", position: "QB", team: "KC", season: 2025)
      expect(rows.first.stats).to include("passing_yards" => 3650, "passing_tds" => 24, "fantasy_points_ppr" => 298.7)
      expect(rows.last.stats).not_to have_key("passing_epa")
    end

    it "saves each season to the processed cache" do
      rows = stats.season(seasons: [2025])
      entry = processed.read("nflverse/player_stats/season/2025", model: SportsIngest::Nflverse::PlayerSeasonStats)

      expect(entry.models).to eq(rows)
    end

    it "raises NotFound when a season's file doesn't exist" do
      stub_request(:get, "#{base}/stats_player_reg_2024.csv").to_return(status: 404)

      expect { stats.season(seasons: [2024]) }.to raise_error(SportsIngest::NotFound)
    end

    it "raises ParseError when a file isn't CSV" do
      publish("stats_player_reg_2025.csv", "player_id,name\n\"unclosed,quote\n")

      expect { stats.season(seasons: [2025]) }.to raise_error(SportsIngest::ParseError)
    end
  end

  it "rejects a season count that isn't positive" do
    expect { stats.weekly(last: 0) }.to raise_error(ArgumentError, /last/)
  end
end
