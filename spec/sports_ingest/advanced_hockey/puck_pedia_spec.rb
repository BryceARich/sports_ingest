# frozen_string_literal: true

require "sports_ingest/advanced_hockey"
require "tmpdir"

RSpec.describe SportsIngest::AdvancedHockey::PuckPedia do
  let(:fixture) { File.expand_path("../../fixtures/advanced_hockey/puckpedia_cap_hit_2026.csv", __dir__) }
  let(:contract_class) { SportsIngest::AdvancedHockey::Contract }
  let(:header) { File.open(fixture, &:readline).chomp }
  let(:good_row) { %(1,"Testerson, Alpha",,24,C,YR 1 OF 5,5.00,9100000,2026-27,2030-31,UFA,Agency,GM) }

  # Writes +lines+ to a temporary CSV and loads it.
  def load_lines(*lines, **options)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "export.csv")
      File.write(path, lines.join("\r\n") + "\r\n")
      described_class.contracts(path, **options)
    end
  end

  describe ".contracts with the 2026 cap-hit layout" do
    subject(:contracts) { described_class.contracts(fixture) }

    it "loads one Contract per player row, skipping the blank helper row" do
      expect(contracts).to all(be_a(contract_class))
      expect(contracts.map(&:name)).to eq(["Alpha Testerson", "Zoé Ébauche", "Bo Placeholder", "Jean-Luc Van Fiction"])
    end

    it "maps every contract column" do
      expect(contracts.first.to_h).to eq(
        name: "Alpha Testerson", first_name: "Alpha", last_name: "Testerson", age: 24, position: "C",
        cap_hit: 9_100_000, contract_year: 1, length: 5, start_season: 2026, expiry_season: 2030,
        expiry_status: "UFA", agent: "Invented Agency", signing_gm: "Pretend GM"
      )
    end

    it "names seasons by their start year and reads mid-deal status" do
      expect(contracts[1].to_h).to include(contract_year: 3, length: 4, start_season: 2024, expiry_season: 2027,
        expiry_status: "UFA-Group6")
    end

    it "keeps blank agent and GM as nil" do
      expect(contracts[2].agent).to be_nil
      expect(contracts[3].signing_gm).to be_nil
    end

    it "round-trips through JSON" do
      contracts.each { |contract| expect(contract_class.from_h(JSON.parse(contract.to_json))).to eq(contract) }
    end

    it "accepts the format by name" do
      expect(described_class.contracts(fixture, format: :cap_hit_2026)).to eq(contracts)
    end

    it "reads formatted dollar amounts and a byte-order mark" do
      row = good_row.sub("9100000", %("$9,100,000"))
      expect(load_lines("﻿#{header}", row).first.cap_hit).to eq(9_100_000)
    end
  end

  describe "errors" do
    it "raises NotFound for a missing file" do
      expect { described_class.contracts("/nonexistent/2026-CAPHIT.csv") }
        .to raise_error(SportsIngest::NotFound) { |e| expect(e.source).to eq(:puckpedia) }
    end

    it "raises ArgumentError for an unknown format name" do
      expect { described_class.contracts(fixture, format: :cap_hit_1999) }.to raise_error(ArgumentError, /cap_hit_2026/)
    end

    it "raises SourceChangedError naming the missing columns when no format matches" do
      expect { load_lines("Player,Team,Current Cap Hit", %("Testerson, Alpha",XXX,1)) }
        .to raise_error(SportsIngest::SourceChangedError, /missing columns Age, Pos, Status/)
    end

    it "raises ParseError for malformed CSV" do
      expect { load_lines(header, %(1,"Testerson, Alpha)) }.to raise_error(SportsIngest::ParseError)
    end

    it "raises ParseError for a file that isn't UTF-8" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "export.csv")
        File.binwrite(path, "#{header}\r\n1,\"\xC9bauche, Zo\xE9\"\r\n")
        expect { described_class.contracts(path) }.to raise_error(SportsIngest::ParseError, /UTF-8/)
      end
    end

    {
      "a name that isn't Last, First" => [%("Testerson, Alpha"), "Alpha Testerson", /line 2: Player .* isn't "Last, First"/],
      "an unknown status" => ["YR 1 OF 5", "Year one", /Status "Year one"/],
      "a status past the deal's end" => ["YR 1 OF 5", "YR 6 OF 5", /Status "YR 6 OF 5"/],
      "an unknown position" => [",C,", ",X,", /Pos "X" is unknown/],
      "a cap hit that isn't dollars" => ["9100000", "TBD", /Cap Hit "TBD"/],
      "a fractional length" => ["5.00", "5.50", /Length "5.50" isn't a whole number/],
      "a malformed season" => ["2030-31", "2030-32", /Expiry Year "2030-32" isn't a season/],
      "a length that disagrees with the seasons" => ["2030-31", "2029-30", /disagree/],
      "a blank expiry status" => [",UFA,", ",,", /Expiry Status is blank/]
    }.each do |problem, (from, to, message)|
      it "raises SourceChangedError with the line for #{problem}" do
        expect { load_lines(header, good_row.sub(from, to)) }
          .to raise_error(SportsIngest::SourceChangedError, message) { |e| expect(e.source).to eq(:puckpedia) }
      end
    end
  end
end
