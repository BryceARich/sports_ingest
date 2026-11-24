# frozen_string_literal: true

require "sports_ingest/nflverse"
require "csv"
require "tmpdir"

RSpec.describe SportsIngest::Nflverse::Players do
  subject(:players) { described_class.new(downloader: downloader, processed: processed) }

  let(:dir) { Pathname.new(Dir.mktmpdir("nflverse-players")) }
  let(:store) { SportsIngest::Cache::MemoryStore.new }
  let(:processed) { SportsIngest::Cache::Processed.new(store: store) }
  let(:downloader) { NflverseFakeDownloader.new(dir, "players.csv" => body) }

  # Invented values with nflverse's real column names (players.csv, M5-03).
  let(:header) do
    %w[gsis_id display_name first_name last_name position birth_date college_name latest_team status last_season]
  end
  let(:body) do
    CSV.generate do |csv|
      csv << header
      csv << ["00-0000001", "Example Runner", "Example", "Runner", "RB", "1990-02-03", "Example U", "GB", "ACT", "2016"]
      csv << ["", "No Id Yet", "No", "Id", "WR", "", "", "", "", ""]
      csv << ["00-0000002", "Sample Kicker", "Sample", "Kicker", "K", "", "", "PIT", "DEV", ""]
    end
  end

  after { FileUtils.rm_rf(dir) }

  def loader(csv_body, processed: nil)
    described_class.new(downloader: NflverseFakeDownloader.new(dir, "players.csv" => csv_body), processed: processed)
  end

  describe "#fetch" do
    it "returns a Player for each row with a gsis_id, in file order" do
      expect(players.fetch.map(&:id)).to eq(%w[00-0000001 00-0000002])
    end

    it "maps the columns onto the Player fields, turning blank cells into nil" do
      runner, kicker = players.fetch

      expect(runner).to have_attributes(display_name: "Example Runner", first_name: "Example",
        last_name: "Runner", position: "RB", birth_date: Date.new(1990, 2, 3), college: "Example U",
        latest_team: "GB", status: "ACT", last_season: 2016)
      expect(runner.ref).to have_attributes(sport: :football, canonical_id: "00-0000001")
      expect(runner.ref.key).to eq("football:00-0000001")

      expect(kicker).to have_attributes(birth_date: nil, college: nil, last_season: nil, latest_team: "PIT")
    end

    it "writes the players to the processed cache under nflverse/players" do
      players.fetch

      entry = processed.read("nflverse/players", model: SportsIngest::Nflverse::Player)
      expect(entry.models.map(&:id)).to eq(%w[00-0000001 00-0000002])
      expect(entry.source).to eq(:nflverse)
    end

    it "reads the players release through the downloader" do
      players.fetch

      expect(downloader.requests).to eq([%w[players players.csv]])
    end

    it "raises SourceChangedError when a column is missing" do
      expect { loader("gsis_id,display_name\n00-0000001,X\n").fetch }
        .to raise_error(SportsIngest::SourceChangedError, /first_name/)
    end

    it "raises SourceChangedError when a gsis_id isn't in nflverse's format" do
      expect { loader(body.sub("00-0000002", "2552")).fetch }
        .to raise_error(SportsIngest::SourceChangedError, /"2552"/)
    end

    it "raises SourceChangedError when a birth date isn't an ISO 8601 date" do
      expect { loader(body.sub("1990-02-03", "February 3")).fetch }
        .to raise_error(SportsIngest::SourceChangedError, /birth_date/)
    end
  end
end
