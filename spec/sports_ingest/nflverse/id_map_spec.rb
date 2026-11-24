# frozen_string_literal: true

require "sports_ingest/nflverse"
require "tmpdir"

RSpec.describe SportsIngest::Nflverse::IdMap do
  subject(:map) { described_class.new(downloader: downloader, processed: processed) }

  let(:base) { "https://github.com/nflverse/nflverse-data/releases/download/players" }
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

  before do
    stub_request(:get, "#{base}/timestamp.json").to_return(status: 200,
      body: JSON.generate("last_updated" => "2026-11-22 05:12:43 EST"), headers: {"Content-Type" => "application/json"})
    stub_request(:get, "#{base}/players.csv").to_return(status: 200, body: fixture("players.csv"),
      headers: {"Content-Type" => "text/csv"})
  end

  describe "#gsis_id" do
    it "maps an ESPN ID to the GSIS ID" do
      expect(map.gsis_id(source: "espn", id: "1002")).to eq("00-0000002")
    end

    it "maps a PFR ID too, given as a symbol" do
      expect(map.gsis_id(source: :pfr, id: "ExamQu00")).to eq("00-0000001")
    end

    it "returns nil for an ID no player has" do
      expect(map.gsis_id(source: "espn", id: "9999")).to be_nil
    end

    it "returns nil for a blank ID, and for a player who has none in that source" do
      expect(map.gsis_id(source: "espn", id: " ")).to be_nil
      expect(map.gsis_id(source: "pfr", id: nil)).to be_nil
    end

    it "returns nil for an ID shared by two GSIS IDs, rather than guessing" do
      expect(map.gsis_id(source: "espn", id: "1004")).to be_nil
    end

    it "raises ArgumentError for a source it doesn't know" do
      expect { map.gsis_id(source: "yahoo", id: "1") }.to raise_error(ArgumentError, /unknown id source/)
    end

    it "raises ArgumentError for Sleeper, which the players file doesn't carry" do
      expect { map.gsis_id(source: "sleeper", id: "2001") }.to raise_error(ArgumentError, /unknown id source/)
    end
  end

  describe "#players" do
    it "returns one PlayerId per row with a GSIS ID, in GSIS ID order" do
      players = map.players

      expect(players).to all(be_a(SportsIngest::Nflverse::PlayerId))
      expect(players.map(&:gsis_id)).to eq(%w[00-0000001 00-0000002 00-0000003 00-0000004 00-0000005])
    end

    it "keeps only the sources a player has an ID in" do
      receiver = map.players.find { it.gsis_id == "00-0000002" }

      expect(receiver).to have_attributes(name: "Example Receiver", position: "WR",
        ids: {"espn" => "1002", "pfr" => "ExamRe00"})
      expect(map.players.find { it.gsis_id == "00-0000003" }.ids).to eq("espn" => "1003")
    end

    it "saves the table to the processed cache" do
      map.players

      entry = processed.read("nflverse/id_map", model: SportsIngest::Nflverse::PlayerId)
      expect(entry.models.map(&:gsis_id)).to eq(%w[00-0000001 00-0000002 00-0000003 00-0000004 00-0000005])
    end
  end

  it "raises SourceChangedError when the file has no gsis_id column" do
    stub_request(:get, "#{base}/players.csv").to_return(status: 200, body: "display_name,espn_id\nX,1\n",
      headers: {"Content-Type" => "text/csv"})

    expect { map.players }.to raise_error(SportsIngest::SourceChangedError, /no gsis_id column/)
  end
end
