# frozen_string_literal: true

require "sports_ingest/advanced_hockey"

RSpec.describe SportsIngest::AdvancedHockey::GoalieGarImport do
  fixtures = File.expand_path("../../fixtures/advanced_hockey", __dir__)
  header = "Player,Season,Team,Position,GP,TOI EV,TOI SH,FA EV,FA SH,EVD,SHD,Take,Draw,GAR,WAR,SPAR"
  row = "Casey Fixturenko,25-26,N.J/WPG,G,20,1180.5,12.3,612.4,6.1,0,0,NA,0,1.2,0.6,0.8"

  def error_for(text)
    described_class.parse(text)
  rescue SportsIngest::Error => e
    e
  end

  describe ".read" do
    let(:by_season) { described_class.read("#{fixtures}/goalie_gar_by_season.csv") }
    let(:by_team) { described_class.read("#{fixtures}/goalie_gar_by_team.csv") }

    it "loads the season grouping row for row, in file order" do
      expect(by_season.map(&:player)).to eq(["Casey Fixturenko", "Dana Placeholder", "Morgan Madeupsen"])
    end

    it "loads the team grouping row for row, a row per team" do
      expect(by_team.map { [it.player, it.teams] }.first(2)).to eq([["Casey Fixturenko", ["N.J"]], ["Casey Fixturenko", ["WPG"]]])
      expect(by_team.size).to eq(4)
    end

    it "reads every column into the model, with spaced headers normalized" do
      expect(by_season.first.to_h).to eq(
        player: "Casey Fixturenko", season: 2026, teams: %w[N.J WPG], position: "G", gp: 20,
        toi_ev: 1180.5, toi_sh: 12.3, fa_ev: 612.4, fa_sh: 6.1, evd: 0.0, shd: 0.0, take: nil,
        draw: 0.0, gar: 1.2, war: 0.6, spar: 0.8
      )
    end

    it "reads NA as nil in a numeric column" do
      expect(by_season.first.take).to be_nil
    end

    it "returns models that round-trip through JSON" do
      expect(by_season.map { |r| SportsIngest::AdvancedHockey::GoalieGar.from_h(JSON.parse(r.to_json)) }).to eq(by_season)
    end

    it "raises NotFound for a missing file" do
      expect { described_class.read("/nonexistent/goalie_gar.csv") }
        .to raise_error(SportsIngest::NotFound) { |e| expect(e.source).to eq(:advanced_hockey) }
    end

    describe "GoalieGar.combine" do
      it "merges a traded goalie's team rows into the season grouping's row" do
        combined = SportsIngest::AdvancedHockey::GoalieGar.combine(by_team)
        expect(combined.first).to eq(by_season.first)
      end

      it "leaves rows already grouped by season unchanged" do
        expect(SportsIngest::AdvancedHockey::GoalieGar.combine(by_season)).to eq(by_season)
      end
    end
  end

  describe ".parse" do
    it "accepts the export's header order" do
      expect(described_class.parse("#{header}\n#{row}\n").first.teams).to eq(%w[N.J WPG])
    end

    it "matches a missing column and names it" do
      error = error_for("Player,Season,Team,Position,GP\n#{row}\n")
      expect(error).to be_a(SportsIngest::SourceChangedError)
      expect(error.message).to include("missing column(s) toi_ev")
    end

    it "names the line and column of a cell that isn't a number" do
      bad = row.sub("1180.5", "lots")
      expect(error_for("#{header}\n#{bad}\n").message).to include("goalie GAR line 2, column toi_ev")
    end
  end
end
