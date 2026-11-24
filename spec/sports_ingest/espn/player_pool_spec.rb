# frozen_string_literal: true

require "sports_ingest/espn"

RSpec.describe SportsIngest::ESPN::PlayerPool do
  subject(:pool) { described_class.new(game: :hockey, client: client, today: Date.new(2026, 11, 23)) }

  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.raw_cache = :off } }
  let(:limiter) { SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}) }
  let(:http) do
    SportsIngest::HTTP::Client.new(source: :espn, rate_limiter: limiter, max_retries: 0, configuration: config)
  end
  let(:client) { SportsIngest::ESPN::Client.new(game: :hockey, http: http, configuration: config) }
  let(:json) { {"Content-Type" => "application/json;charset=utf-8"} }
  let(:hockey) { "https://lm-api-reads.fantasy.espn.com/apis/v3/games/fhl" }
  let(:football) { "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl" }

  # One player with an actual season total, a projection and a weekly line. Values are invented.
  let(:player) do
    {
      "id" => 4_000_001, "fullName" => "Test Skater", "proTeamId" => 10, "defaultPositionId" => 3,
      "stats" => [
        {"seasonId" => 2027, "scoringPeriodId" => 0, "statSourceId" => 0, "statSplitTypeId" => 0,
         "stats" => {"13" => 1.0, "25" => 12.0}, "appliedTotal" => 99.0},
        {"seasonId" => 2027, "scoringPeriodId" => 0, "statSourceId" => 1, "statSplitTypeId" => 0,
         "stats" => {"25" => 30.0}},
        {"seasonId" => 2027, "scoringPeriodId" => 4, "statSourceId" => 0, "statSplitTypeId" => 5,
         "stats" => {"25" => 1.0}}
      ]
    }
  end

  def stub_pool(base, espn_id, body)
    stub_request(:get, "#{base}/seasons/#{espn_id}/players?view=kona_player_info")
      .to_return(status: 200, headers: json, body: JSON.generate(body))
  end

  describe ".new" do
    it "rejects an unknown game" do
      expect { described_class.new(game: :curling) }.to raise_error(ArgumentError, /game must be one of/)
    end
  end

  describe "#current_season" do
    it "is the start year, with hockey rolling over in October and football in August" do
      expect(pool.current_season).to eq(2026)
      expect(described_class.new(game: :hockey, today: Date.new(2026, 7, 1)).current_season).to eq(2025)
      expect(described_class.new(game: :football, client: client, today: Date.new(2026, 8, 15)).current_season)
        .to eq(2026)
      expect(described_class.new(game: :football, client: client, today: Date.new(2026, 7, 1)).current_season)
        .to eq(2025)
    end
  end

  describe "#espn_season_id" do
    it "names hockey seasons by the year they end and football ones by the year they start" do
      expect(pool.espn_season_id(2026)).to eq(2027)
      expect(described_class.new(game: :football, client: client).espn_season_id(2026)).to eq(2026)
    end
  end

  describe "#actual_stats" do
    it "loads the last three seasons by default, using each game's ESPN season IDs" do
      stub_pool(hockey, 2025, [])
      stub_pool(hockey, 2026, [])
      stub_pool(hockey, 2027, [])

      expect(pool.actual_stats).to eq([])
      expect(a_request(:get, "#{hockey}/seasons/2025/players?view=kona_player_info")).to have_been_made.once
      expect(a_request(:get, "#{hockey}/seasons/2027/players?view=kona_player_info")).to have_been_made.once
    end

    it "loads football's last three seasons under the same start years" do
      football_client = SportsIngest::ESPN::Client.new(game: :football, http: http, configuration: config)
      football_pool = described_class.new(game: :football, client: football_client, today: Date.new(2026, 11, 23))
      %w[2024 2025 2026].each { stub_pool(football, it, []) }

      expect(football_pool.actual_stats(last: 3)).to eq([])
      expect(a_request(:get, "#{football}/seasons/2024/players?view=kona_player_info")).to have_been_made.once
      expect(a_request(:get, "#{football}/seasons/2026/players?view=kona_player_info")).to have_been_made.once
    end

    it "keeps only the actual season total, and returns the raw stat lines, not applied points" do
      stub_pool(hockey, 2027, [player])

      rows = pool.actual_stats(seasons: [2026])

      expect(rows.size).to eq(1)
      expect(rows.first).to have_attributes(player_id: 4_000_001, full_name: "Test Skater", pro_team_id: 10,
        default_position_id: 3, game: :hockey, season: 2026, stats: {"13" => 1.0, "25" => 12.0})
    end

    it "skips a player with no season total or an empty one" do
      empty = player.merge("id" => 4_000_002, "stats" => [{"seasonId" => 2027, "scoringPeriodId" => 0,
                                                           "statSourceId" => 0, "statSplitTypeId" => 0, "stats" => {}}])
      stub_pool(hockey, 2027, [player, empty, {"id" => 4_000_003, "fullName" => "Free Agent", "stats" => []}])

      expect(pool.actual_stats(seasons: [2026]).map(&:player_id)).to eq([4_000_001])
    end

    it "sends the limit as a filter" do
      stub_request(:get, "#{hockey}/seasons/2027/players?view=kona_player_info")
        .with(headers: {"X-Fantasy-Filter" => '{"players":{"limit":50}}'})
        .to_return(status: 200, headers: json, body: "[]")

      pool.actual_stats(seasons: [2026], limit: 50)
      expect(a_request(:get, "#{hockey}/seasons/2027/players?view=kona_player_info")).to have_been_made.once
    end

    it "sends no filter when no limit is given" do
      stub_pool(hockey, 2027, [])

      pool.actual_stats(seasons: [2026])
      expect(a_request(:get, "#{hockey}/seasons/2027/players?view=kona_player_info")
        .with { |req| req.headers.keys.none? { it.casecmp?("X-Fantasy-Filter") } }).to have_been_made.once
    end

    it "raises a clear NotFound when ESPN keeps no data for a season" do
      stub_request(:get, "#{hockey}/seasons/2006/players?view=kona_player_info")
        .to_return(status: 404, headers: json, body: '{"messages":["Not Found"]}')

      expect { pool.actual_stats(seasons: [2005]) }
        .to raise_error(SportsIngest::NotFound, /no hockey data for the 2005 season \(ESPN season 2006\)/)
    end

    it "raises SourceChangedError when the pool isn't an array" do
      stub_request(:get, "#{hockey}/seasons/2027/players?view=kona_player_info")
        .to_return(status: 200, headers: json, body: '{"players":[]}')

      expect { pool.actual_stats(seasons: [2026]) }
        .to raise_error(SportsIngest::SourceChangedError, /player pool should be a JSON array/)
    end

    it "rejects both keywords, and a bad limit, before any request" do
      expect { pool.actual_stats(seasons: [2025], last: 2) }.to raise_error(ArgumentError, /not both/)
      expect { pool.actual_stats(last: 2, limit: 0) }.to raise_error(ArgumentError, /limit must be/)
      expect(a_request(:any, /espn/)).not_to have_been_made
    end

    it "saves each season to the processed cache when given one" do
      processed = instance_double(SportsIngest::Cache::Processed)
      allow(processed).to receive(:write)
      stub_pool(hockey, 2027, [player])
      described_class.new(game: :hockey, client: client, processed: processed, today: Date.new(2026, 11, 23))
        .actual_stats(seasons: [2026])

      expect(processed).to have_received(:write).with("espn/player_stats/hockey/2027/actual", anything,
        source: :espn, fetched_at: anything, model: SportsIngest::ESPN::PlayerStats)
    end
  end
end
