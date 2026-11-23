# frozen_string_literal: true

require "open3"
require "tmpdir"
require_relative "../../script/lib/licensed_data_guard"

RSpec.describe LicensedDataGuard do
  root = File.expand_path("../..", __dir__)
  # Header shaped like an Evolving-Hockey skater export; every value is invented.
  eh_export = "Player,EH_ID,Season,Team,Position,GP,TOI,GAR,WAR\n" \
              "Test Skater,TEST.SKATER,24-25,AAA,C,82,1500.5,12.3,2.1\n"

  describe ".violations" do
    it "flags an Evolving-Hockey export by its name" do
      expect(described_class.violations("EH_std_sk_stats_5v5_regular.csv")).not_to be_empty
    end

    it "flags PuckPedia and Evolving-Hockey names, including compressed files" do
      expect(described_class.violations("data/puckpedia_contracts.xlsx")).not_to be_empty
      expect(described_class.violations("tmp/evolving-hockey-gar.csv.gz")).not_to be_empty
    end

    it "flags a renamed export by its EH_ID column" do
      expect(described_class.violations("stats.csv", eh_export)).to include(/EH_ID/)
    end

    it "flags a processed cache that names the source" do
      expect(described_class.violations("cache/players.json", '{"source":"evolving_hockey"}')).not_to be_empty
    end

    it "allows code and docs that name the sources" do
      expect(described_class.violations("lib/sports_ingest/advanced_hockey/puckpedia.rb", "PuckPedia EH_ID")).to be_empty
      expect(described_class.violations("docs/sources/evolving_hockey.md", "EH_ID")).to be_empty
    end

    it "allows unrelated data and words that merely contain 'eh'" do
      expect(described_class.violations("spec/fixtures/nhl/teh_schedule.json", '{"games":[]}')).to be_empty
    end

    it "allows invented-value fixtures in spec/fixtures/advanced_hockey/" do
      expect(described_class.violations("spec/fixtures/advanced_hockey/EH_skaters.csv", eh_export)).to be_empty
    end

    it "handles binary content" do
      expect(described_class.violations("stats.csv", "\xFF\xFEEH_ID".b)).not_to be_empty
    end
  end

  describe "the pre-commit hook" do
    def git(dir, *args)
      out, status = Open3.capture2e("git", "-c", "user.name=Spec", "-c", "user.email=spec@example.com", *args, chdir: dir)
      [out, status.success?]
    end

    around do |example|
      Dir.mktmpdir do |dir|
        @repo = dir
        git(dir, "init", "-q")
        git(dir, "config", "core.hooksPath", File.join(root, ".githooks"))
        example.run
      end
    end

    it "blocks committing a sample Evolving-Hockey export" do
      File.write(File.join(@repo, "EH_std_sk_stats.csv"), eh_export)
      git(@repo, "add", ".")
      out, ok = git(@repo, "commit", "-q", "-m", "add export")

      expect(ok).to be(false)
      expect(out).to include("EH_std_sk_stats.csv")
    end

    it "lets other files through" do
      File.write(File.join(@repo, "notes.md"), "Evolving-Hockey exports stay outside the repo.\n")
      git(@repo, "add", ".")

      expect(git(@repo, "commit", "-q", "-m", "add notes").last).to be(true)
    end
  end

  describe "the CI check (--range)" do
    it "finds an export added and then deleted within the range" do
      Dir.mktmpdir do |dir|
        run = ->(*args) { Open3.capture2e("git", "-c", "user.name=Spec", "-c", "user.email=spec@example.com", *args, chdir: dir) }
        run.call("init", "-q")
        run.call("commit", "-q", "--allow-empty", "-m", "base")
        File.write(File.join(dir, "stats.csv"), eh_export)
        run.call("add", ".")
        run.call("commit", "-q", "-m", "add")
        run.call("rm", "-q", "stats.csv")
        run.call("commit", "-q", "-m", "remove")

        out, status = Open3.capture2e("ruby", File.join(root, "script/licensed-data-guard"), "--range", "HEAD~2..HEAD", chdir: dir)
        expect(status.success?).to be(false)
        expect(out).to include("stats.csv")
      end
    end
  end
end
