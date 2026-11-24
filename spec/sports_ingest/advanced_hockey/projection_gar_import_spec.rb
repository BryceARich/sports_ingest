# frozen_string_literal: true

require "sports_ingest/advanced_hockey"

RSpec.describe SportsIngest::AdvancedHockey::ProjectionGarImport do
  fixtures = File.expand_path("../../fixtures/advanced_hockey", __dir__)
  header = "Player,Season,Team,Position,TOI All,EVO,EVD,PPO,SHD,Take,Draw,GAR,GAR-,GAR+,GAR/60,GAR/60-,GAR/60+,GAR Unc"
  row = "Avery Testwood,26-27,N.J/WPG,C,612.4,1.2,-0.3,0.8,0.1,0.2,0.4,2.1,-0.8,4.9,0.31,0.12,0.5,0.09"

  def error_for(text)
    described_class.parse(text)
  rescue SportsIngest::Error => e
    e
  end

  describe ".read" do
    let(:rows) { described_class.read("#{fixtures}/gar_projections.csv") }

    it "loads the projection tab row for row, skipping blank rows" do
      expect(rows.map(&:player)).to eq(["Avery Testwood", "Blake Fixturson", "Casey Placeholder", "Dana Madeupski"])
    end

    it "reads every column into the model, with signs kept from the headers" do
      expect(rows.first.to_h).to eq(
        player: "Avery Testwood", season: 2026, teams: %w[N.J WPG], position: "C", toi_all: 612.4,
        evo: 1.2, evd: -0.3, ppo: 0.8, shd: 0.1, take: 0.2, draw: 0.4,
        gar: 2.1, gar_minus: -0.8, gar_plus: 4.9, gar_60: 0.31, gar_60_minus: 0.12, gar_60_plus: 0.5,
        uncertainty: 0.09
      )
    end

    it "reads NA and - as nil" do
      expect(rows[2].to_h.values_at(:gar, :gar_minus)).to eq([nil, nil])
    end

    it "returns models that round-trip through JSON" do
      expect(rows.map { |r| SportsIngest::AdvancedHockey::ProjectionGar.from_h(JSON.parse(r.to_json)) }).to eq(rows)
    end

    it "raises NotFound for a missing file" do
      expect { described_class.read("/nonexistent/gar_projections.csv") }
        .to raise_error(SportsIngest::NotFound) { |e| expect(e.source).to eq(:advanced_hockey) }
    end
  end

  describe ".parse" do
    it "matches headers regardless of case and spacing, and ignores extra columns" do
      loose = header.downcase + ",Age\n#{row},31\n"
      expect(described_class.parse(loose).first.gar_plus).to eq(4.9)
    end

    it "keeps the low and high ends apart from the point estimate" do
      parsed = described_class.parse("#{header}\n#{row}\n").first
      expect([parsed.gar, parsed.gar_minus, parsed.gar_plus]).to eq([2.1, -0.8, 4.9])
    end

    it "raises SourceChangedError naming a missing column" do
      error = error_for("#{header.sub(",GAR/60+", "")}\n")
      expect(error).to be_a(SportsIngest::SourceChangedError)
      expect(error.message).to include("missing column(s) gar_60_plus")
    end

    it "raises SourceChangedError with the line and column for a non-numeric GAR" do
      error = error_for("#{header}\n#{row}\n#{row.sub("2.1", "lots")}\n")
      expect(error).to be_a(SportsIngest::SourceChangedError)
      expect(error.message).to include("GAR projections line 3, column gar")
    end

    it "raises ParseError for malformed CSV" do
      expect(error_for(%(#{header}\n"unclosed,26-27\n))).to be_a(SportsIngest::ParseError)
    end
  end
end
