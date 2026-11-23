# frozen_string_literal: true

require "sports_ingest/advanced_hockey"

RSpec.describe SportsIngest::AdvancedHockey::SkaterGarImport do
  fixtures = File.expand_path("../../fixtures/advanced_hockey", __dir__)
  header = "Player,Season,Team,Position,GP,TOI_All,EVO_GAR,EVD_GAR,PPO_GAR,SHD_GAR," \
    "Take_GAR,Draw_GAR,Off_GAR,Def_GAR,Pens_GAR,GAR,WAR,SPAR"
  row = "Avery Testwood,25-26,VAN,C,82,1612.4,9.8,1.2,3.1,0.4,-0.6,1.1,12.9,1.6,0.5,15.0,2.7,5.3"

  def error_for(text)
    described_class.parse(text)
  rescue SportsIngest::Error => e
    e
  end

  # EH exports the table grouped by season (a traded player's row reads "N.J/WPG") or by team
  # and season (a row per team), with the same columns.
  describe ".read" do
    let(:by_season) { described_class.read("#{fixtures}/skater_gar_by_season.csv") }
    let(:by_team) { described_class.read("#{fixtures}/skater_gar_by_team.csv") }

    it "loads the season grouping row for row, in file order" do
      expect(by_season.map(&:player)).to eq(
        ["Avery Testwood", "Blake Fixturson", "Casey Placeholder", "Dana Madeupski", "Dana Madeupski (D)", "Émile Inventé"]
      )
    end

    it "loads the team grouping row for row, a row per team" do
      expect(by_team.map { [it.player, it.teams] }.first(2)).to eq([["Avery Testwood", ["N.J"]], ["Avery Testwood", ["WPG"]]])
      expect(by_team.size).to eq(7)
    end

    it "reads every column into the model" do
      expect(by_season.first.to_h).to eq(
        player: "Avery Testwood", season: 2026, teams: %w[N.J WPG], position: "C", gp: 22, toi_all: 355.7,
        evo_gar: 3.5, evd_gar: -0.7, ppo_gar: 1.4, shd_gar: 0.1, take_gar: 0.1, draw_gar: 0.2,
        off_gar: 4.9, def_gar: -0.6, pens_gar: 0.3, gar: 4.6, war: 0.9, spar: 1.5
      )
    end

    it "splits multi-team values and keeps EH's team abbreviations" do
      expect(by_season.map(&:teams)).to eq([%w[N.J WPG], %w[L.A], %w[MTL NSH], %w[S.J], %w[S.J], %w[T.B]])
    end

    it "returns models that round-trip through JSON" do
      expect(by_season.map { |r| SportsIngest::AdvancedHockey::SkaterGar.from_h(JSON.parse(r.to_json)) }).to eq(by_season)
    end

    it "raises NotFound for a missing file" do
      expect { described_class.read("/nonexistent/skater_gar.csv") }
        .to raise_error(SportsIngest::NotFound) { |e| expect(e.source).to eq(:advanced_hockey) }
    end

    describe "SkaterGar.combine" do
      let(:combined) { SportsIngest::AdvancedHockey::SkaterGar.combine(by_team) }

      it "merges a traded player's team rows into the season grouping's row" do
        expect(combined.first).to eq(by_season.first)
      end

      it "returns one row per player and season, keeping players EH tells apart by name" do
        expect(combined.map(&:player)).to eq(by_season.map(&:player))
      end

      it "leaves rows already grouped by season unchanged" do
        expect(SportsIngest::AdvancedHockey::SkaterGar.combine(by_season)).to eq(by_season)
      end

      it "can't restore a stint the team grouping left out" do
        casey = combined.find { it.player == "Casey Placeholder" }
        expect([casey.teams, casey.gp]).to eq([%w[NSH], 17])
      end

      it "sums to nil when a part is missing" do
        rows = described_class.parse("#{header}\n#{row}\n#{row.sub("VAN", "MIN").sub("2.7", "NA")}\n")
        expect(SportsIngest::AdvancedHockey::SkaterGar.combine(rows).first.to_h.values_at(:teams, :gp, :war))
          .to eq([%w[VAN MIN], 164, nil])
      end
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

    it "reads NA, - and blank numbers as nil" do
      parsed = described_class.parse("#{header}\n#{row.sub("0.4,-0.6,1.1", "NA,-,")}\n").first
      expect([parsed.shd_gar, parsed.take_gar, parsed.draw_gar]).to eq([nil, nil, nil])
    end

    it "skips all-blank rows, as spreadsheet exports leave at the end" do
      expect(described_class.parse("#{header}\n#{row}\n#{"," * 17}\n").size).to eq(1)
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
