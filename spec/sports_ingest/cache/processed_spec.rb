# frozen_string_literal: true

require "tmpdir"

RSpec.describe SportsIngest::Cache::Processed do
  subject(:cache) { described_class.new(store: store, configuration: config, clock: -> { now }) }

  let(:now) { Time.utc(2026, 11, 22, 12, 0, 0) }
  let(:fetched_at) { Time.utc(2026, 11, 22, 11, 30, 0, 123_456) }
  let(:store) { SportsIngest::Cache::MemoryStore.new }
  let(:config) { SportsIngest::Configuration.new(env: {}) }
  let(:key) { "nhl/skaters/2025" }

  let(:team_class) { SportsIngest::Model.define(:abbrev, :name) }
  let(:skater_class) do
    team_model = team_class
    SportsIngest::Model.define(:player, :team, :position, :goals, :toi, :tags, :stats, :born_on, schema_version: 3) do
      define_method(:initialize) do |player:, team:, position:, born_on:, **fields|
        super(player: SportsIngest::Identity::PlayerRef.coerce(player), team: team_model.coerce(team),
              position: position&.to_sym, born_on: born_on && Date.iso8601(born_on.to_s), **fields)
      end
    end
  end
  let(:skaters) do
    [
      skater_class.new(
        player: SportsIngest::Identity::PlayerRef.new(sport: :hockey, canonical_id: 8478402, source_ids: {espn: 3895074}),
        team: {abbrev: "EDM", name: "Edmonton Oilers"}, position: :c, goals: 32, toi: 1312.5,
        tags: ["captain", "ü"], stats: {"pp" => {"goals" => 10}}, born_on: Date.new(1997, 1, 13)
      ),
      skater_class.new(
        player: {sport: "hockey", canonical_id: "8477934"}, team: nil, position: nil, goals: 0,
        toi: 0.0, tags: [], stats: {}, born_on: nil
      )
    ]
  end

  before do
    stub_const("Team", team_class)
    stub_const("Skater", skater_class)
  end

  describe "round trip" do
    it "reads back an equal collection with its metadata" do
      cache.write(key, skaters, source: :nhl, fetched_at: fetched_at)
      entry = cache.read(key, model: Skater)

      expect(entry.models).to eq(skaters)
      expect(entry).to have_attributes(model: Skater, source: :nhl, schema_version: 3,
        fetched_at: fetched_at, written_at: now)
      expect(entry.models).to all(be_frozen)
    end

    it "round-trips through a disk store, in a new process's worth of objects" do
      Dir.mktmpdir do |dir|
        disk = described_class.new(store: SportsIngest::Cache::DiskStore.new(dir), clock: -> { now })
        disk.write(key, skaters, source: "nhl", fetched_at: fetched_at)
        reread = described_class.new(store: SportsIngest::Cache::DiskStore.new(dir), clock: -> { now })

        expect(reread.read(key, model: Skater).models).to eq(skaters)
        expect(File.stat(File.join(dir, "#{key}.json")).mode & 0o777).to eq(0o600)
      end
    end

    it "round-trips PlayerRefs, symbols and all" do
      refs = skaters.map(&:player)
      cache.write("nhl/refs", refs, source: :nhl)

      expect(cache.read("nhl/refs", model: SportsIngest::Identity::PlayerRef).models).to eq(refs)
    end

    it "round-trips an empty collection when the model is named" do
      cache.write(key, [], source: :nhl, model: Skater)

      expect(cache.read(key, model: Skater).models).to eq([])
    end

    it "returns from #write what #read returns" do
      expect(cache.write(key, skaters, source: :nhl, fetched_at: fetched_at)).to eq(cache.read(key, model: Skater))
    end

    it "defaults fetched_at to now" do
      expect(cache.write(key, skaters, source: :nhl).fetched_at).to eq(now)
    end
  end

  describe "#write" do
    it "replaces an earlier entry" do
      cache.write(key, skaters, source: :nhl)
      cache.write(key, skaters.take(1), source: :nhl)

      expect(cache.read(key, model: Skater).models.size).to eq(1)
    end

    it "rejects a model whose fields don't survive JSON, and stores nothing" do
      loose = SportsIngest::Model.define(:position)
      stub_const("Loose", loose)

      expect { cache.write(key, [Loose.new(position: :c)], source: :nhl) }
        .to raise_error(ArgumentError, /Loose item 0 doesn't read back unchanged/)
      expect(store.read(key)).to be_nil
    end

    it "rejects a model that can't be rebuilt from its JSON" do
      wrapper = SportsIngest::Model.define(:team) do
        define_method(:initialize) { |team:| super(team: team.is_a?(Hash) ? raise(ArgumentError, "a Hash") : team) }
      end
      stub_const("Wrapper", wrapper)

      expect { cache.write(key, [Wrapper.new(team: Team.new(abbrev: "EDM", name: "E"))], source: :nhl) }
        .to raise_error(ArgumentError, /Wrapper doesn't read back from JSON/)
    end

    it "rejects values JSON can't hold" do
      expect { cache.write(key, [Team.new(abbrev: "EDM", name: Float::NAN)], source: :nhl) }
        .to raise_error(ArgumentError, /can't be written as JSON/)
    end

    it "rejects mixed, anonymous or non-model collections" do
      expect { cache.write(key, [skaters.first, Team.new(abbrev: "E", name: "E")], source: :nhl) }
        .to raise_error(ArgumentError, /every model must be a Skater/)
      expect { cache.write(key, [SportsIngest::Model.define(:a).new(a: 1)], source: :nhl) }
        .to raise_error(ArgumentError, /has no name/)
      expect { cache.write(key, [{a: 1}], source: :nhl) }.to raise_error(ArgumentError, /Model.define/)
      expect { cache.write(key, [], source: :nhl) }.to raise_error(ArgumentError, /Model.define/)
      expect { cache.write(key, skaters.first, source: :nhl) }.to raise_error(ArgumentError, /Array/)
    end

    it "rejects a bad source or key" do
      expect { cache.write(key, skaters, source: "NHL!") }.to raise_error(ArgumentError, /snake_case/)
      expect { cache.write(key, skaters, source: nil) }.to raise_error(ArgumentError)
      expect { cache.write("../escape", skaters, source: :nhl) }.to raise_error(SportsIngest::ConfigurationError)
    end
  end

  describe "#read misses" do
    before { cache.write(key, skaters, source: :nhl, fetched_at: fetched_at) }

    it "misses with no entry" do
      expect(cache.read("nhl/other", model: Skater)).to be_nil
    end

    it "misses for another model class" do
      expect(cache.read(key, model: Team)).to be_nil
    end

    it "misses when the model's schema version changed" do
      stub_const("Skater::SCHEMA_VERSION", 4)

      expect(cache.read(key, model: Skater)).to be_nil
    end

    it "misses when the entry layout version changed" do
      stub_const("#{described_class}::FORMAT_VERSION", 2)

      expect(cache.read(key, model: Skater)).to be_nil
    end

    it "misses when older than max_age" do
      expect(cache.read(key, model: Skater, max_age: 1800)).not_to be_nil
      expect(cache.read(key, model: Skater, max_age: 1799)).to be_nil
    end

    it "misses on a damaged entry" do
      good = store.read(key)
      [
        good.merge("models" => [{"nope" => 1}]),
        good.merge("models" => nil),
        good.merge("fetched_at" => "yesterday"),
        good.except("source"),
        ["not", "a", "hash"]
      ].each do |damaged|
        store.write(key, damaged)
        expect(cache.read(key, model: Skater)).to be_nil
      end
    end
  end

  describe "#delete" do
    it "removes the entry" do
      cache.write(key, skaters, source: :nhl)
      cache.delete(key)

      expect(cache.read(key, model: Skater)).to be_nil
    end
  end

  describe "store selection" do
    it "uses the configured mode" do
      config.processed_cache = :off
      off = described_class.new(configuration: config)
      off.write(key, skaters, source: :nhl)

      expect(off.read(key, model: Skater)).to be_nil
    end

    it "keeps its memory store apart from the raw tier's" do
      expect(described_class.store_for(:memory)).to be(described_class.store_for(:memory))
      expect(described_class.store_for(:memory)).not_to be(SportsIngest::Cache::Raw.store_for(:memory))
    end

    it "puts the disk store under cache_dir/processed" do
      expect(described_class.store_for(:disk, config).dir).to eq(config.cache_dir.join("processed"))
    end

    it "rejects an unknown mode or tier" do
      expect { described_class.store_for(:redis) }.to raise_error(SportsIngest::ConfigurationError)
      expect { SportsIngest::Cache.store_for(:memory, tier: :other) }.to raise_error(SportsIngest::ConfigurationError)
    end
  end

  it "never shows cached contents in #inspect" do
    cache.write(key, skaters, source: :nhl)

    expect(cache.inspect).not_to include("Edmonton")
  end
end
