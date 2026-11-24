# frozen_string_literal: true

require "stringio"
require "sports_ingest/advanced_hockey"

RSpec.describe SportsIngest::AdvancedHockey::SkaterGarImport, ".report" do
  known = Struct.new(:ref, :full_name, :birth_date, :position, :team)
  fixtures = File.expand_path("../../fixtures/advanced_hockey", __dir__)

  # Only Avery Testwood is known, so the EH rows that name him match on name alone.
  let(:matcher) do
    SportsIngest::Identity::Matcher.new([
      known.new(SportsIngest::Identity::PlayerRef.new(sport: :hockey, canonical_id: 8400001),
        "Avery Testwood", "1999-05-01", "C", "NJD")
    ])
  end

  it "prints the rows that need review and returns the full report" do
    io = StringIO.new
    report = described_class.report("#{fixtures}/skater_gar_by_season.csv", matcher: matcher, io: io)

    expect(io.string).to start_with("Identity report: 6 records,")
    expect(io.string).to include("Avery Testwood")
    expect(report.rows.size).to eq(6)
    expect(report.review.map { it.name }).to include("Avery Testwood")
  end

  it "matches a traded player on name and position, without a team" do
    report = described_class.report("#{fixtures}/skater_gar_by_season.csv", matcher: matcher, io: nil)
    avery = report.rows.find { it.name == "Avery Testwood" }

    expect([avery.team, avery.match.reason, avery.match.confidence]).to eq([nil, :unique_name, :low])
  end

  it "stays quiet when io is nil" do
    expect { described_class.report("#{fixtures}/skater_gar_by_season.csv", matcher: matcher, io: nil) }
      .not_to output.to_stdout
  end
end
