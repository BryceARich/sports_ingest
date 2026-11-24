# frozen_string_literal: true

require "sports_ingest/advanced_hockey"

RSpec.describe SportsIngest::AdvancedHockey::ProjectionGarImport do
  fixtures = File.expand_path("../../fixtures/advanced_hockey", __dir__)
  header = "Player,Team,Position,GAR,GAR_Minus,GAR_Plus,GAR_60,Uncertainty"
  row = "Avery Testwood,N.J/WPG,C,2.1,-0.8,4.9,0.31,0.12"

  def error_for(text)
    described_class.parse(text, season: 2026)
  rescue SportsIngest::Error => e
    e
  end

  describe ".read" do
    let(:rows) { described_class.read("#{fixtures}/gar_projections.csv", season: 2026) }

    it "loads the projection tab row for row, skipping blank rows" do
      expect(rows.map(&:player)).to eq(["Avery Testwood", "Blake Fixturson", "Casey Placeholder", "Dana Madeupski"])
    end

    it "reads every column into the model, with the season it was given" do
      expect(rows.first.to_h).to eq(
        player: "Avery Testwood", season: 2026, teams: %w[N.J WPG], position: "C",
        gar: 2.1, gar_minus: -0.8, gar_plus: 4.9, gar_60: 0.31, uncertainty: 0.12
      )
    end

    it "reads NA and - as nil" do
      expect(rows[2].to_h.values_at(:gar, :gar_minus)).to eq([nil, nil])
    end

    it "returns models that round-trip through JSON" do
      expect(rows.map { |r| SportsIngest::AdvancedHockey::ProjectionGar.from_h(JSON.parse(r.to_json)) }).to eq(rows)
    end

    it "raises NotFound for a missing file" do
      expect { described_class.read("/nonexistent/gar_projections.csv", season: 2026) }
        .to raise_error(SportsIngest::NotFound) { |e| expect(e.source).to eq(:advanced_hockey) }
    end
  end

  describe ".parse" do
    it "matches headers regardless of case and spacing, and ignores extra columns" do
      loose = header.tr("_", " ").downcase + ",Age\n#{row},31\n"
      expect(described_class.parse(loose, season: 2026).first.gar_plus).to eq(4.9)
    end

    it "reads the season it is given, not one from the file" do
      expect(described_class.parse("#{header}\n#{row}\n", season: 2030).first.season).to eq(2030)
    end

    it "raises SourceChangedError naming a missing column" do
      error = error_for("#{header.sub(",GAR_60", "")}\n")
      expect(error).to be_a(SportsIngest::SourceChangedError)
      expect(error.message).to include("missing column(s) gar_60")
    end

    it "raises SourceChangedError with the line and column for a non-numeric GAR" do
      error = error_for("#{header}\n#{row}\n#{row.sub("2.1", "lots")}\n")
      expect(error).to be_a(SportsIngest::SourceChangedError)
      expect(error.message).to include("GAR projections line 3, column gar")
    end

    it "raises ParseError for malformed CSV" do
      expect(error_for(%(#{header}\n"unclosed,C\n))).to be_a(SportsIngest::ParseError)
    end
  end
end
