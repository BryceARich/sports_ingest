# frozen_string_literal: true

require "sports_ingest/nflverse"
require "tmpdir"

RSpec.describe SportsIngest::Nflverse::ReleaseDownloader do
  subject(:downloader) { build }

  let(:base) { "https://github.com/nflverse/nflverse-data/releases/download/players" }
  let(:timestamp_url) { "#{base}/timestamp.json" }
  let(:file_url) { "#{base}/players.csv" }
  let(:now) { Time.utc(2026, 11, 23, 12, 0, 0) }
  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.ttls = {nflverse: 0} } }
  let(:store) { SportsIngest::Cache::MemoryStore.new }
  let(:client) do
    SportsIngest::HTTP::Client.new(source: :nflverse, max_retries: 0, configuration: config,
      rate_limiter: SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}))
  end
  let(:dir) { Pathname.new(Dir.mktmpdir("nflverse")) }

  after { FileUtils.rm_rf(dir) }

  def build(ttl: 0)
    timestamps = SportsIngest::Cache::Raw.new(client: client, store: store, ttl: ttl, configuration: config)
    described_class.new(client: client, timestamps: timestamps, dir: dir, configuration: config, clock: -> { now })
  end

  def stamp(value)
    stub_request(:get, timestamp_url).to_return(status: 200, body: JSON.generate("last_updated" => value),
      headers: {"Content-Type" => "application/json"})
  end

  def asset(body)
    stub_request(:get, file_url).to_return(status: 200, body: body, headers: {"Content-Type" => "text/csv"})
  end

  describe "#fetch" do
    it "downloads the asset to <dir>/<tag>/<file> and records the upstream timestamp" do
      stamp("2026-11-22 05:12:43 EST")
      asset("gsis_id,display_name\n00-0012345,Example Player\n")

      release = downloader.fetch("players", "players.csv")

      expect(release).to have_attributes(path: dir.join("players", "players.csv"), tag: "players",
        file: "players.csv", url: file_url, last_updated: "2026-11-22 05:12:43 EST", fetched_at: now, stale: false)
      expect(release.path.read).to eq("gsis_id,display_name\n00-0012345,Example Player\n")
      expect(release.path.stat.mode & 0o777).to eq(0o600)
    end

    it "downloads a file once and reuses it while upstream is unchanged" do
      stamp("2026-11-22 05:12:43 EST")
      asset("v1")

      first = downloader.fetch("players", "players.csv")
      second = build.fetch("players", "players.csv")

      expect(a_request(:get, file_url)).to have_been_made.once
      expect(a_request(:get, timestamp_url)).to have_been_made.twice
      expect(second).to have_attributes(path: first.path, fetched_at: now, stale: false)
    end

    it "downloads it again once timestamp.json changes" do
      stamp("2026-11-22 05:12:43 EST")
      asset("v1")
      downloader.fetch("players", "players.csv")

      stamp("2026-11-23 05:10:00 EST")
      asset("v2")
      release = build.fetch("players", "players.csv")

      expect(a_request(:get, file_url)).to have_been_made.twice
      expect(release).to have_attributes(last_updated: "2026-11-23 05:10:00 EST", stale: false)
      expect(release.path.read).to eq("v2")
    end

    it "checks timestamp.json at most once per TTL" do
      stamp("2026-11-22 05:12:43 EST")
      asset("v1")
      cached = build(ttl: 3600)
      2.times { cached.fetch("players", "players.csv") }

      expect(a_request(:get, timestamp_url)).to have_been_made.once
    end

    it "keeps binary assets byte for byte" do
      bytes = (0..255).map(&:chr).join.b
      stamp("2026-11-22 05:12:43 EST")
      stub_request(:get, "#{base}/players.parquet").to_return(status: 200, body: bytes,
        headers: {"Content-Type" => "application/octet-stream"})

      expect(downloader.fetch("players", "players.parquet").path.binread).to eq(bytes)
    end

    it "downloads again if the record beside the file is missing or damaged" do
      stamp("2026-11-22 05:12:43 EST")
      asset("v1")
      release = downloader.fetch("players", "players.csv")
      File.write("#{release.path}.meta.json", "{not json")
      downloader.fetch("players", "players.csv")

      expect(a_request(:get, file_url)).to have_been_made.twice
    end

    it "returns the local copy marked stale when the timestamp check can't reach the network" do
      stamp("2026-11-22 05:12:43 EST")
      asset("v1")
      downloader.fetch("players", "players.csv")

      stub_request(:get, timestamp_url).to_timeout
      release = downloader.fetch("players", "players.csv")

      expect(release).to have_attributes(stale: true, last_updated: "2026-11-22 05:12:43 EST")
      expect(release.path.read).to eq("v1")
    end

    it "returns the local copy marked stale when the new download fails with a 5xx" do
      stamp("2026-11-22 05:12:43 EST")
      asset("v1")
      downloader.fetch("players", "players.csv")

      stamp("2026-11-23 05:10:00 EST")
      stub_request(:get, file_url).to_return(status: 503)
      release = downloader.fetch("players", "players.csv")

      expect(release).to have_attributes(stale: true, last_updated: "2026-11-22 05:12:43 EST")
      expect(release.path.read).to eq("v1")
    end

    it "returns the local copy marked stale when the raw cache has no timestamp to fall back on" do
      stamp("2026-11-22 05:12:43 EST")
      asset("v1")
      downloader.fetch("players", "players.csv")
      store.clear

      stub_request(:get, timestamp_url).to_return(status: 502)
      expect(downloader.fetch("players", "players.csv")).to have_attributes(stale: true)
    end

    it "raises the network error when there's no local copy" do
      stub_request(:get, timestamp_url).to_timeout

      expect { downloader.fetch("players", "players.csv") }.to raise_error(SportsIngest::HTTPError)
    end

    it "raises NotFound for an asset that doesn't exist" do
      stamp("2026-11-22 05:12:43 EST")
      stub_request(:get, "#{base}/nope.csv").to_return(status: 404)

      expect { downloader.fetch("players", "nope.csv") }.to raise_error(SportsIngest::NotFound)
    end

    it "raises SourceChangedError when timestamp.json has no last_updated" do
      stub_request(:get, timestamp_url).to_return(status: 200, body: '{"updated":"x"}',
        headers: {"Content-Type" => "application/json"})

      expect { downloader.fetch("players", "players.csv") }.to raise_error(SportsIngest::SourceChangedError)
    end

    it "raises ParseError when timestamp.json isn't JSON" do
      stub_request(:get, timestamp_url).to_return(status: 200, body: "<html>",
        headers: {"Content-Type" => "text/html"})

      expect { downloader.fetch("players", "players.csv") }.to raise_error(SportsIngest::ParseError)
    end

    it "rejects tags and names that aren't plain file names" do
      ["../etc", "a/b", ".hidden", "", "players.csv.meta.json"].each do |name|
        expect { downloader.fetch("players", name) }.to raise_error(ArgumentError)
        expect { downloader.fetch(name, "players.csv") }.to raise_error(ArgumentError)
      end
    end

    it "raises a gem error when the file can't be written" do
      stamp("2026-11-22 05:12:43 EST")
      asset("v1")
      File.write(dir.join("players"), "a file where the tag folder goes")

      expect { downloader.fetch("players", "players.csv") }.to raise_error(SportsIngest::Error, /can't write/)
    end
  end

  describe "defaults" do
    it "keeps assets under <cache_dir>/releases/nflverse" do
      config.cache_dir = dir.to_s

      expect(described_class.new(configuration: config).dir).to eq(dir.join("releases", "nflverse"))
    end
  end

  it "names its directory in #inspect" do
    expect(downloader.inspect).to include("dir=#{dir}")
  end
end
