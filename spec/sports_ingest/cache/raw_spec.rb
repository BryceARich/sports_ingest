# frozen_string_literal: true

require "tmpdir"

RSpec.describe SportsIngest::Cache::Raw do
  subject(:cache) { described_class.new(client: client, store: store, configuration: config, clock: -> { now }) }

  let(:url) { "https://api.example.test/v1/standings" }
  let(:now) { Time.utc(2026, 11, 22, 12, 0, 0) }
  let(:store) { SportsIngest::Cache::MemoryStore.new }
  let(:config) { SportsIngest::Configuration.new(env: {}).tap { |c| c.ttls = {nhl: 600} } }
  let(:client) do
    SportsIngest::HTTP::Client.new(source: :nhl, max_retries: 0, configuration: config,
      rate_limiter: SportsIngest::HTTP::RateLimiter.new(interval: 0, sleeper: ->(_) {}))
  end

  def fetch_once
    allow(Time).to receive(:now).and_return(now)
    cache.get(url).tap { allow(Time).to receive(:now).and_call_original }
  end

  describe "#get" do
    before do
      stub_request(:get, url).to_return(status: 200, body: '{"ok":true}',
        headers: {"Content-Type" => "application/json", "Set-Cookie" => "session=xyz"})
    end

    it "makes no HTTP request for a second identical call within the TTL" do
      first = fetch_once
      now_later = now + 599
      second = described_class.new(client: client, store: store, configuration: config, clock: -> { now_later }).get(url)

      expect(a_request(:get, url)).to have_been_made.once
      expect(second).to have_attributes(status: 200, body: '{"ok":true}', url: url, stale: false,
        fetched_at: first.fetched_at)
      expect(second.body.encoding).to eq(Encoding::UTF_8)
    end

    it "refetches once the TTL has passed" do
      fetch_once
      described_class.new(client: client, store: store, configuration: config, clock: -> { now + 600 }).get(url)

      expect(a_request(:get, url)).to have_been_made.twice
    end

    it "always refetches with a TTL of 0" do
      zero = described_class.new(client: client, store: store, ttl: 0)
      2.times { zero.get(url) }

      expect(a_request(:get, url)).to have_been_made.twice
    end

    it "keys on params and headers" do
      stub_request(:get, "#{url}?season=2025").to_return(status: 200, body: "season")
      fetch_once
      cache.get(url, params: {season: 2025})
      cache.get(url, headers: {"Cookie" => SportsIngest::Secret.new("espn_s2=a")})

      expect(a_request(:get, url)).to have_been_made.twice
      expect(a_request(:get, "#{url}?season=2025")).to have_been_made.once
    end

    it "doesn't store Set-Cookie or request headers" do
      cache.get(url, headers: {"Cookie" => SportsIngest::Secret.new("espn_s2=topsecret")})
      entry = store.read(cache.key_for(url, {}, {"Cookie" => SportsIngest::Secret.new("espn_s2=topsecret")}))

      expect(entry["headers"]).not_to have_key("set-cookie")
      expect(JSON.generate(entry)).not_to include("topsecret")
    end

    it "serves the cached response, marked stale, when the network errors" do
      fetch_once
      stub_request(:get, url).to_timeout
      later = described_class.new(client: client, store: store, configuration: config, clock: -> { now + 5_999 })

      response = later.get(url)

      expect(response).to have_attributes(status: 200, body: '{"ok":true}', stale: true, fetched_at: now)
      expect(response).to be_stale
    end

    it "serves stale on a 5xx or 429 after retries" do
      fetch_once
      later = described_class.new(client: client, store: store, configuration: config, clock: -> { now + 3600 })

      stub_request(:get, url).to_return(status: 503)
      expect(later.get(url)).to be_stale
      stub_request(:get, url).to_return(status: 429)
      expect(later.get(url)).to be_stale
    end

    it "raises AuthError and NotFound even with a cached copy" do
      fetch_once
      later = described_class.new(client: client, store: store, configuration: config, clock: -> { now + 86_400 })

      stub_request(:get, url).to_return(status: 401)
      expect { later.get(url) }.to raise_error(SportsIngest::AuthError)
      stub_request(:get, url).to_return(status: 404)
      expect { later.get(url) }.to raise_error(SportsIngest::NotFound)
    end

    it "raises the HTTPError when nothing is cached" do
      stub_request(:get, url).to_timeout

      expect { cache.get(url) }.to raise_error(SportsIngest::HTTPError) { |e| expect(e.status).to be_nil }
    end

    it "round-trips binary bodies through the disk store" do
      Dir.mktmpdir do |dir|
        disk = described_class.new(client: client, store: SportsIngest::Cache::DiskStore.new(dir), ttl: 600)
        bytes = "\x00\xFF\xFEparquet".b
        stub_request(:get, url).to_return(status: 200, body: bytes, headers: {"Content-Type" => "application/octet-stream"})

        disk.get(url)
        cached = disk.get(url)

        expect(a_request(:get, url)).to have_been_made.once
        expect(cached.body).to eq(bytes)
        expect(cached.body.encoding).to eq(Encoding::BINARY)
      end
    end

    it "reads a damaged entry as a miss" do
      store.write(cache.key_for(url), {"schema_version" => 1, "status" => 200})

      expect(cache.get(url).body).to eq('{"ok":true}')
    end
  end

  describe "eviction" do
    # nhl's TTL is 600 in `config`, so entries are evicted at 6000 seconds by default.
    def cache_at(time, **options)
      described_class.new(client: client, store: store, configuration: config, clock: -> { time }, **options)
    end

    before { stub_request(:get, url).to_return(status: 200, body: '{"ok":true}') }

    it "serves stale up to 10 x TTL with no settings" do
      fetch_once
      stub_request(:get, url).to_timeout

      expect(cache_at(now + 5_999).get(url)).to be_stale
    end

    it "refetches an evicted entry when the network works" do
      fetch_once
      cache_at(now + 6_000).get(url)

      expect(a_request(:get, url)).to have_been_made.twice
    end

    it "raises instead of serving an evicted entry stale, and leaves no file behind" do
      Dir.mktmpdir do |dir|
        disk = SportsIngest::Cache::DiskStore.new(dir)
        allow(Time).to receive(:now).and_return(now)
        described_class.new(client: client, store: disk, configuration: config, clock: -> { now }).get(url)
        allow(Time).to receive(:now).and_call_original
        stub_request(:get, url).to_timeout

        later = described_class.new(client: client, store: disk, configuration: config, clock: -> { now + 6_000 })

        expect { later.get(url) }.to raise_error(SportsIngest::HTTPError)
        expect(disk.keys).to be_empty
        expect(Dir.glob("#{dir}/**/*.json")).to be_empty
      end
    end

    it "uses the configured eviction age" do
      config.evict_after = {nhl: 60}
      fetch_once
      stub_request(:get, url).to_timeout

      expect { cache_at(now + 60).get(url) }.to raise_error(SportsIngest::HTTPError)
    end

    it "never evicts with an eviction age of 0" do
      fetch_once
      stub_request(:get, url).to_timeout

      expect(cache_at(now + (365 * 86_400), evict_after: 0).get(url)).to be_stale
    end

    it "derives the age from a ttl given to the cache" do
      fetch_once
      stub_request(:get, url).to_timeout

      expect(cache_at(now + 59_999, ttl: 6_000).get(url)).to be_stale
      expect { cache_at(now + 60_000, ttl: 6_000).get(url) }.to raise_error(SportsIngest::HTTPError)
    end

    it "rejects a negative evict_after" do
      expect { described_class.new(client: client, evict_after: -1) }.to raise_error(SportsIngest::ConfigurationError)
    end
  end

  describe "#prune" do
    let(:fresh_key) { cache.key_for(url) }

    def entry(fetched_at)
      {"schema_version" => 1, "status" => 200, "headers" => {}, "url" => url,
       "fetched_at" => fetched_at.utc.iso8601(6), "encoding" => "UTF-8", "body" => "x"}
    end

    it "deletes expired entries for every source, damaged ones too, and keeps the rest" do
      Dir.mktmpdir do |dir|
        disk = SportsIngest::Cache::DiskStore.new(dir)
        old_cookie = cache.key_for(url, {}, {"Cookie" => SportsIngest::Secret.new("espn_s2=old")})
          .sub("nhl/", "espn/")
        disk.write(fresh_key, entry(now - 5_999))           # nhl, within 10 x 600
        disk.write("nhl/aa/old", entry(now - 6_000))        # nhl, evicted
        disk.write(old_cookie, entry(now - 9_000))          # espn: 10 x 900, evicted
        disk.write("espn/bb/recent", entry(now - 8_999))    # espn, kept
        disk.write("nhl/cc/damaged", {"schema_version" => 1})
        disk.write("future_source/dd/v2", entry(now - 36_000).merge("schema_version" => 2)) # 10 x default 3600

        deleted = cache.prune(disk)

        expect(deleted).to eq(4)
        expect(disk.keys).to contain_exactly(fresh_key, "espn/bb/recent")
      end
    end

    it "sweeps the store on its own after a write, at most once an hour" do
      Dir.mktmpdir do |dir|
        disk = SportsIngest::Cache::DiskStore.new(dir)
        stub_request(:get, %r{api\.example\.test}).to_return(status: 200, body: "x")
        at = ->(time) { described_class.new(client: client, store: disk, configuration: config, clock: -> { time }) }

        disk.write("nhl/aa/old", entry(now - 6_000))
        at.call(now).get(url)
        expect(disk.read("nhl/aa/old")).to be_nil

        disk.write("nhl/aa/old", entry(now - 6_000))
        at.call(now + 3_599).get("#{url}/2")
        expect(disk.read("nhl/aa/old")).not_to be_nil

        at.call(now + 3_600).get("#{url}/3")
        expect(disk.read("nhl/aa/old")).to be_nil
      end
    end
  end

  describe "store selection" do
    it "uses the configured mode" do
      config.raw_cache = :off
      cache = described_class.new(client: client, configuration: config)
      2.times { cache.get(url) }

      expect(a_request(:get, url)).to have_been_made.twice
    end

    it "shares one memory store across instances" do
      expect(described_class.store_for(:memory)).to be(described_class.store_for(:memory))
    end

    it "puts the disk store under cache_dir/raw" do
      expect(described_class.store_for(:disk, config).dir).to eq(config.cache_dir.join("raw"))
    end

    it "rejects an unknown mode" do
      expect { described_class.store_for(:redis) }.to raise_error(SportsIngest::ConfigurationError)
    end

    before { stub_request(:get, url).to_return(status: 200, body: "x") }
  end

  it "rejects a negative ttl" do
    expect { described_class.new(client: client, ttl: -1) }.to raise_error(SportsIngest::ConfigurationError)
  end

  it "doesn't show header values in the key" do
    key = cache.key_for(url, {}, {"Cookie" => SportsIngest::Secret.new("espn_s2=abc")})

    expect(key).to match(%r{\Anhl/\h{2}/\h{64}\z})
  end
end
