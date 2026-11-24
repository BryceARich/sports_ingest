# frozen_string_literal: true

require "sports_ingest/nflverse"
require "csv"
require "tmpdir"

RSpec.describe SportsIngest::Nflverse::Rosters do
  subject(:rosters) { described_class.new(downloader: downloader, processed: processed) }

  let(:dir) { Pathname.new(Dir.mktmpdir("nflverse-rosters")) }
  let(:store) { SportsIngest::Cache::MemoryStore.new }
  let(:processed) { SportsIngest::Cache::Processed.new(store: store) }
  let(:downloader) { NflverseFakeDownloader.new(dir, "roster_2025.csv" => body) }

  # Invented values with nflverse's real column names (rosters release, M5-03). The file has more
  # columns than these; only the ones read are listed.
  let(:header) do
    %w[season team position jersey_number status full_name gsis_id]
  end
  let(:body) do
    CSV.generate do |csv|
      csv << header
      csv << ["2025", "PIT", "RB", "25", "ACT", "Example Runner", "00-0000001"]
      csv << ["2025", "GB", "DL", "", "DEV", "Sample Lineman", "00-0000003"]
      csv << ["2025", "GB", "K", "3", "RES", "Sample Kicker", "00-0000002"]
      csv << ["2025", "GB", "K", "4", "RES", "Unlisted Kicker", ""]
    end
  end

  after { FileUtils.rm_rf(dir) }

  def loader(csv_body)
    described_class.new(downloader: NflverseFakeDownloader.new(dir, "roster_2025.csv" => csv_body), processed: nil)
  end

  describe "#fetch" do
    it "returns an entry for each row with a gsis_id, in file order, skipping the blank one" do
      expect(rosters.fetch(2025).map(&:id)).to eq(%w[00-0000001 00-0000003 00-0000002])
    end

    it "maps each row onto a RosterEntry, with the season the file was asked for" do
      runner, _lineman, kicker = rosters.fetch(2025)

      expect(runner).to have_attributes(season: 2025, team: "PIT", position: "RB", jersey_number: 25,
        status: "ACT", full_name: "Example Runner")
      expect(runner.ref).to have_attributes(sport: :football, canonical_id: "00-0000001")
      expect(kicker).to have_attributes(team: "GB", jersey_number: 3, status: "RES")
    end

    it "reads roster_<season>.csv from the rosters release" do
      rosters.fetch(2025)

      expect(downloader.requests).to eq([%w[rosters roster_2025.csv]])
    end

    it "writes the entries to the processed cache under nflverse/rosters/<season>" do
      rosters.fetch(2025)

      entry = processed.read("nflverse/rosters/2025", model: SportsIngest::Nflverse::RosterEntry)
      expect(entry.models.map(&:id)).to eq(%w[00-0000001 00-0000003 00-0000002])
    end

    it "turns a blank jersey number into nil" do
      expect(rosters.fetch(2025)[1]).to have_attributes(full_name: "Sample Lineman", jersey_number: nil)
    end

    it "raises ArgumentError for a season that isn't a positive Integer" do
      expect { rosters.fetch("2025") }.to raise_error(ArgumentError, /season/)
      expect { rosters.fetch(0) }.to raise_error(ArgumentError, /season/)
    end

    it "raises SourceChangedError when a column is missing" do
      expect { loader("season,gsis_id\n2025,00-0000001\n").fetch(2025) }
        .to raise_error(SportsIngest::SourceChangedError, /full_name/)
    end

    it "raises SourceChangedError when a gsis_id isn't in nflverse's format" do
      expect { loader(body.sub("00-0000002", "x")).fetch(2025) }
        .to raise_error(SportsIngest::SourceChangedError, /"x"/)
    end
  end
end
