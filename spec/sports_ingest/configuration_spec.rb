# frozen_string_literal: true

require "json"
require "pp"
require "stringio"

RSpec.describe SportsIngest::Configuration do
  # Invented values; never put real cookies in specs.
  let(:s2) { "FAKE-espn-s2-cookie-value" }
  let(:swid) { "{00000000-0000-0000-0000-000000000000}" }
  let(:env) { {"XDG_CACHE_HOME" => "/xdg/cache"} }

  subject(:config) { described_class.new(env: env) }

  describe "defaults" do
    it "puts the cache under XDG_CACHE_HOME" do
      expect(config.cache_dir).to eq(Pathname.new("/xdg/cache/sports_ingest"))
    end

    it "falls back to ~/.cache when XDG_CACHE_HOME is unset" do
      expect(described_class.new(env: {}).cache_dir)
        .to eq(Pathname.new(File.join(Dir.home, ".cache", "sports_ingest")))
    end

    it "keeps the default cache dir outside the repository" do
      repo = File.expand_path("../..", __dir__)
      expect(described_class.new(env: {}).cache_dir.to_s).not_to start_with(repo)
    end

    it "names the gem and its version in the user agent" do
      expect(config.user_agent).to start_with("sports_ingest/#{SportsIngest::VERSION} ")
    end

    it "has per-source TTLs and a default for other sources" do
      expect(config.ttl_for(:nhl)).to eq(3600)
      expect(config.ttl_for("espn")).to eq(900)
      expect(config.ttl_for(:nflverse)).to eq(86_400)
      expect(config.ttl_for(:something_else)).to eq(described_class::DEFAULT_TTL)
    end

    it "has no ESPN cookies" do
      expect(config.espn_s2).to be_nil
      expect(config.espn_swid).to be_nil
      expect(config).not_to be_espn_credentials
    end
  end

  describe "loading from env" do
    let(:env) do
      {
        "SPORTS_INGEST_CACHE_DIR" => "/env/cache",
        "SPORTS_INGEST_USER_AGENT" => "test-agent/1.0",
        "SPORTS_INGEST_TTL" => "120",
        "SPORTS_INGEST_RAW_CACHE" => "Memory",
        "SPORTS_INGEST_PROCESSED_CACHE" => "off",
        "SPORTS_INGEST_TTL_NHL" => "60",
        "SPORTS_INGEST_TTL_PUCKPEDIA" => "0",
        "SPORTS_INGEST_EVICT_AFTER" => "86400",
        "SPORTS_INGEST_EVICT_AFTER_ESPN" => "7200",
        "SPORTS_INGEST_ESPN_S2" => s2,
        "SPORTS_INGEST_ESPN_SWID" => swid,
        "UNRELATED" => "ignored"
      }
    end

    it "reads every setting" do
      expect(config.cache_dir).to eq(Pathname.new("/env/cache"))
      expect(config.user_agent).to eq("test-agent/1.0")
      expect(config.default_ttl).to eq(120)
      expect(config.raw_cache).to eq(:memory)
      expect(config.processed_cache).to eq(:off)
      expect(config.ttl_for(:nhl)).to eq(60)
      expect(config.ttl_for(:puckpedia)).to eq(0)
      expect(config.ttl_for(:espn)).to eq(900)
      expect(config.ttl_for(:other)).to eq(120)
      expect(config.default_evict_after).to eq(86_400)
      expect(config.evict_after_for(:espn)).to eq(7200)
      expect(config.evict_after_for(:nhl)).to eq(86_400)
      expect(config.espn_s2.reveal).to eq(s2)
      expect(config.espn_swid.reveal).to eq(swid)
      expect(config).to be_espn_credentials
    end

    it "treats empty variables as unset" do
      cfg = described_class.new(env: env.merge("SPORTS_INGEST_ESPN_S2" => "", "SPORTS_INGEST_TTL_NHL" => " "))
      expect(cfg.espn_s2).to be_nil
      expect(cfg.ttl_for(:nhl)).to eq(3600)
    end

    it "rejects a non-numeric TTL" do
      expect { described_class.new(env: {"SPORTS_INGEST_TTL_NHL" => "soon"}) }
        .to raise_error(SportsIngest::ConfigurationError, /ttls\[nhl\]/)
    end
  end

  describe "setters" do
    it "expands ~ in cache_dir" do
      config.cache_dir = "~/somewhere"
      expect(config.cache_dir).to eq(Pathname.new(File.join(Dir.home, "somewhere")))
    end

    it "merges ttls over the current ones" do
      config.ttls = {"nhl" => 10, "custom" => "20"}
      expect(config.ttls).to include(nhl: 10, custom: 20, espn: 900)
    end

    it "does not let callers mutate ttls in place" do
      expect { config.ttls[:nhl] = 1 }.to raise_error(FrozenError)
    end

    it "rejects negative or non-integer TTLs" do
      expect { config.default_ttl = -1 }.to raise_error(SportsIngest::ConfigurationError)
      expect { config.default_ttl = 1.5 }.to raise_error(SportsIngest::ConfigurationError)
      expect { config.ttls = {nhl: "1h"} }.to raise_error(SportsIngest::ConfigurationError)
      expect { config.ttls = [] }.to raise_error(SportsIngest::ConfigurationError)
    end

    it "evicts at 10 x each source's TTL by default" do
      cfg = described_class.new(env: {})
      expect(cfg.default_evict_after).to be_nil
      expect(cfg.evict_after).to eq({})
      expect(cfg.evict_after_for(:nhl)).to eq(36_000)
      expect(cfg.evict_after_for(:espn)).to eq(9_000)
      expect(cfg.evict_after_for(:nflverse)).to eq(864_000)
      expect(cfg.evict_after_for(:nhl, ttl: 60)).to eq(600)
    end

    it "falls back to default_ttl for a source with a TTL of 0" do
      config.ttls = {nhl: 0}
      expect(config.evict_after_for(:nhl)).to eq(10 * config.default_ttl)
    end

    it "takes a per-source age over the default, and nil to unset either" do
      config.default_evict_after = "600"
      config.evict_after = {"espn" => 60}
      expect(config.evict_after_for(:espn)).to eq(60)
      expect(config.evict_after_for(:nhl)).to eq(600)

      config.evict_after = {espn: nil}
      config.default_evict_after = nil
      expect(config.evict_after_for(:espn)).to eq(9_000)
    end

    it "rejects invalid eviction ages" do
      expect { config.default_evict_after = -1 }.to raise_error(SportsIngest::ConfigurationError)
      expect { config.evict_after = {nhl: "later"} }.to raise_error(SportsIngest::ConfigurationError)
      expect { config.evict_after = [] }.to raise_error(SportsIngest::ConfigurationError)
    end

    it "keeps the raw cache on disk by default and accepts memory or off" do
      expect(described_class.new(env: {}).raw_cache).to eq(:disk)
      config.raw_cache = "off"
      expect(config.raw_cache).to eq(:off)
      expect { config.raw_cache = :redis }.to raise_error(SportsIngest::ConfigurationError)
      expect { config.raw_cache = nil }.to raise_error(SportsIngest::ConfigurationError)
    end

    it "keeps the processed cache on disk by default and accepts memory or off" do
      expect(described_class.new(env: {}).processed_cache).to eq(:disk)
      config.processed_cache = :memory
      expect(config.processed_cache).to eq(:memory)
      expect(config.to_h[:processed_cache]).to eq(:memory)
      expect { config.processed_cache = "redis" }.to raise_error(SportsIngest::ConfigurationError, /processed_cache/)
    end

    it "rejects a blank cache dir or user agent" do
      expect { config.cache_dir = "" }.to raise_error(SportsIngest::ConfigurationError)
      expect { config.user_agent = " " }.to raise_error(SportsIngest::ConfigurationError)
    end

    it "wraps ESPN cookies in secrets and clears them with nil" do
      config.espn_s2 = s2
      expect(config.espn_s2).to eq(SportsIngest::Secret.new(s2))
      config.espn_s2 = nil
      expect(config.espn_s2).to be_nil
    end

    it "rejects an empty cookie" do
      expect { config.espn_swid = "" }.to raise_error(SportsIngest::ConfigurationError)
    end
  end

  describe "redaction" do
    before do
      config.espn_s2 = s2
      config.espn_swid = swid
    end

    def expect_redacted(text)
      expect(text).not_to include(s2)
      expect(text).not_to include(swid)
      expect(text).to include("[REDACTED]")
    end

    it "redacts secrets in inspect and to_s" do
      expect_redacted(config.inspect)
      expect_redacted(config.to_s)
      expect_redacted("#{config.espn_s2} #{config.espn_swid.inspect}")
    end

    it "redacts secrets in pp output" do
      expect_redacted(PP.pp(config, +""))
      expect_redacted(PP.pp(config.espn_s2, +""))
    end

    it "redacts secrets in to_h and its JSON" do
      expect_redacted(config.to_h.to_s)
      expect_redacted(JSON.generate(config.to_h))
      expect_redacted(JSON.generate(cookie: config.espn_s2))
    end

    it "redacts secrets in log lines" do
      io = StringIO.new
      io.puts(config)
      io.puts("cookie=#{config.espn_s2}")
      io.write(config.espn_swid, "\n")
      io.printf("%s %p\n", config.espn_s2, config)
      expect_redacted(io.string)
    end

    it "redacts secrets written to stderr with warn" do
      expect { warn(config, "cookie=#{config.espn_swid}") }.to output(/\[REDACTED\]/).to_stderr
      expect { warn(config, "cookie=#{config.espn_swid}") }.not_to output(/#{Regexp.escape(s2)}|#{Regexp.escape(swid)}/).to_stderr
    end

    it "redacts secrets in error messages that interpolate them" do
      error = SportsIngest::Error.new("auth failed with #{config.espn_s2}")
      expect_redacted(error.full_message)
    end
  end
end

RSpec.describe SportsIngest::Secret do
  it "requires a non-empty String" do
    expect { described_class.new(nil) }.to raise_error(SportsIngest::ConfigurationError)
    expect { described_class.new(123) }.to raise_error(SportsIngest::ConfigurationError)
  end

  it "is frozen and does not share the caller's string" do
    raw = +"abc"
    secret = described_class.new(raw)
    raw << "def"
    expect(secret).to be_frozen
    expect(secret.reveal).to eq("abc")
  end

  it "compares by value" do
    expect(described_class.new("a")).to eq(described_class.new("a"))
    expect(described_class.new("a")).not_to eq(described_class.new("b"))
    expect(described_class.new("a")).not_to eq("a")
    expect(described_class.new("a").hash).to eq(described_class.new("a").hash)
  end
end

RSpec.describe SportsIngest do
  after { described_class.reset_configuration! }

  it "builds one configuration from the environment and reuses it" do
    expect(described_class.configuration).to be_a(SportsIngest::Configuration)
    expect(described_class.configuration).to equal(described_class.configuration)
  end

  it "lets a configure block override env values" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SPORTS_INGEST_USER_AGENT").and_return("from-env/1.0")
    described_class.reset_configuration!

    expect(described_class.configuration.user_agent).to eq("from-env/1.0")
    returned = described_class.configure { |c| c.user_agent = "from-block/1.0" }
    expect(returned.user_agent).to eq("from-block/1.0")
    expect(described_class.configuration.user_agent).to eq("from-block/1.0")
  end

  it "rebuilds the configuration after reset_configuration!" do
    described_class.configure { |c| c.default_ttl = 5 }
    described_class.reset_configuration!
    expect(described_class.configuration.default_ttl).to eq(SportsIngest::Configuration::DEFAULT_TTL)
  end
end
