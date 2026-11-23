# frozen_string_literal: true

require "sports_ingest/advanced_hockey"

RSpec.describe SportsIngest::AdvancedHockey::SkaterGarImport do
  fixture = File.expand_path("../../fixtures/advanced_hockey/skater_gar.csv", __dir__)
  header = "Player,Season,Team,Position,GP,TOI_All,EVO_GAR,EVD_GAR,PPO_GAR,SHD_GAR," \
    "Take_GAR,Draw_GAR,Off_GAR,Def_GAR,Pens_GAR,GAR,WAR,SPAR"
  row = "Avery Testwood,25-26,VAN,C,82,1612.4,9.8,1.2,3.1,0.4,-0.6,1.1,12.9,1.6,0.5,15.0,2.7,5.3"

  def error_for(text)
    described_class.parse(text)
  rescue SportsIngest::Error => e
    e
  end

  describe ".read" do
    subject(:rows) { described_class.read(fixture) }

    it "loads the table row for row, in file order, skipping blank rows" do
      expect(rows.map(&:player)).to eq(["Avery Testwood", "Blake Fixturson", "Casey Placeholder", "Dana Madeupski"])
    end

    it "reads every column into the model" do
      expect(rows.first.to_h).to eq(
        player: "Avery Testwood", season: 2025, teams: %w[VAN MIN], position: "C", gp: 82, toi_all: 1612.4,
        evo_gar: 9.8, evd_gar: 1.2, ppo_gar: 3.1, shd_gar: 0.4, take_gar: -0.6, draw_gar: 1.1,
        off_gar: 12.9, def_gar: 1.6, pens_gar: 0.5, gar: 15.0, war: 2.7, spar: 5.3
      )
    end

    it "splits multi-team values" do
      expect(rows.map(&:teams)).to eq([%w[VAN MIN], %w[TOR], %w[SEA], %w[CGY BOS NSH]])
    end

    it "reads NA as nil" do
      expect(rows.last.shd_gar).to be_nil
    end

    it "returns models that round-trip through JSON" do
      expect(rows.map { |r| SportsIngest::AdvancedHockey::SkaterGar.from_h(JSON.parse(r.to_json)) }).to eq(rows)
    end

    it "raises NotFound for a missing file" do
      expect { described_class.read("/nonexistent/skater_gar.csv") }
        .to raise_error(SportsIngest::NotFound) { |e| expect(e.source).to eq(:advanced_hockey) }
    end
  end

  describe ".parse" do
    it "matches headers regardless of case, spacing and a byte-order mark, and ignores extra columns" do
      loose = "\uFEFF" + header.tr("_", " ").downcase + ",Age\n#{row},31\n"
      expect(described_class.parse(loose).first.gar).to eq(15.0)
    end

    {
      "25-26" => 2025, "2025-26" => 2025, "2025-2026" => 2025, "20252026" => 2025, "2025" => 2025, "07-08" => 2007
    }.each do |season, year|
      it "reads season #{season} as #{year}" do
        expect(described_class.parse("#{header}\n#{row.sub("25-26", season)}\n").first.season).to eq(year)
      end
    end

    it "accepts whole decimals for GP and thousands separators" do
      parsed = described_class.parse("#{header}\n#{row.sub(",82,1612.4,", %(,82.0,"1,612.4",))}\n").first
      expect([parsed.gp, parsed.toi_all]).to eq([82, 1612.4])
    end

    it "returns an empty list for a header with no rows" do
      expect(described_class.parse("#{header}\n")).to eq([])
    end

    it "raises SourceChangedError naming a missing column" do
      error = error_for("#{header.sub(",WAR", "")}\n")
      expect(error).to be_a(SportsIngest::SourceChangedError)
      expect(error.message).to include("missing column(s) war")
    end

    {
      "a season it can't read" => ["25-26", "2025-27", "column season"],
      "a non-numeric GAR" => [",15.0,", ",lots,", "column gar"],
      "a fractional GP" => [",82,", ",81.5,", "column gp"],
      "a blank player" => ["Avery Testwood", "", "column player"]
    }.each do |what, (from, to, column)|
      it "raises SourceChangedError with the line and column for #{what}" do
        error = error_for("#{header}\n#{row}\n#{row.sub(from, to)}\n")
        expect(error).to be_a(SportsIngest::SourceChangedError)
        expect(error.message).to include("skater GAR line 3, #{column}")
      end
    end

    it "raises ParseError for malformed CSV" do
      expect(error_for(%(#{header}\n"unclosed,25-26\n))).to be_a(SportsIngest::ParseError)
    end
  end
end
