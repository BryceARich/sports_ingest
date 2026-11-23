# frozen_string_literal: true

require "tmpdir"
require_relative "../../rakelib/lib/changelog"

RSpec.describe RepoTools::Changelog do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  let(:fragments_dir) { File.join(@dir, "changelog.d") }
  let(:changelog_path) { File.join(@dir, "CHANGELOG.md") }
  let(:changelog) { described_class.new(changelog_path: changelog_path, fragments_dir: fragments_dir) }

  def fragment(name, text)
    FileUtils.mkdir_p(fragments_dir)
    File.write(File.join(fragments_dir, name), text)
  end

  before do
    File.write(changelog_path, <<~MD)
      # Changelog

      Intro.

      ## [Unreleased]

      ### Added

      - Legacy entry that wraps
        onto a second line (M1-01).

      ## [0.0.1] - 2026-01-01

      ### Added

      - First release.
    MD
  end

  describe ".parse" do
    it "groups entries by type and keeps wrapped lines" do
      sections = described_class.parse("### Fixed\n\n- One\n  more\n- Two\n\n### Added\n- Three\n", "f")
      expect(sections).to eq("Fixed" => ["- One\n  more", "- Two"], "Added" => ["- Three"])
    end

    it "rejects an unknown section type" do
      expect { described_class.parse("### Improved\n- x\n", "f.md") }
        .to raise_error(RepoTools::Error, /f\.md:1: unknown section "Improved"/)
    end

    it "rejects an entry before any section" do
      expect { described_class.parse("- x\n", "f.md") }.to raise_error(RepoTools::Error, /entry before/)
    end

    it "rejects stray text" do
      expect { described_class.parse("### Added\nprose\n", "f.md") }.to raise_error(RepoTools::Error, /f\.md:2/)
    end
  end

  describe "#fragment_paths" do
    it "lists fragments highest issue first and skips README.md and dotfiles" do
      fragment("9.md", "")
      fragment("72.md", "")
      fragment("72-ci.md", "")
      fragment("README.md", "")
      fragment(".keep", "")
      expect(changelog.fragment_paths.map { |path| File.basename(path) }).to eq(%w[72-ci.md 72.md 9.md])
    end

    it "rejects files not named after an issue" do
      fragment("notes.md", "")
      expect { changelog.fragment_paths }.to raise_error(RepoTools::Error, /notes\.md/)
    end

    it "is empty when there is no fragments directory" do
      expect(changelog.fragment_paths).to eq([])
    end
  end

  describe "#compile!" do
    before do
      fragment("8.md", "### Added\n\n- HTTP client (M1-05).\n")
      fragment("72.md", "### Changed\n\n- Fragments (#72).\n\n### Added\n\n- Rake tasks (#72).\n")
    end

    it "writes a Keep a Changelog release under an empty Unreleased heading" do
      changelog.compile!(version: "0.2.0", date: "2026-12-01")

      expect(File.read(changelog_path)).to eq(<<~MD)
        # Changelog

        Intro.

        ## [Unreleased]

        ## [0.2.0] - 2026-12-01

        ### Added

        - Rake tasks (#72).
        - HTTP client (M1-05).
        - Legacy entry that wraps
          onto a second line (M1-01).

        ### Changed

        - Fragments (#72).

        ## [0.0.1] - 2026-01-01

        ### Added

        - First release.
      MD
    end

    it "deletes the fragments it used" do
      changelog.compile!(version: "0.2.0", date: "2026-12-01")
      expect(Dir.children(fragments_dir)).to be_empty
    end

    it "refuses a version that is already released" do
      expect { changelog.compile!(version: "0.0.1", date: "2026-12-01") }
        .to raise_error(RepoTools::Error, /already has a \[0\.0\.1\]/)
    end

    it "refuses when there is nothing to release" do
      FileUtils.rm_rf(fragments_dir)
      File.write(changelog_path, "# Changelog\n\n## [Unreleased]\n")
      expect { changelog.compile!(version: "0.2.0", date: "2026-12-01") }
        .to raise_error(RepoTools::Error, /nothing to release/)
    end
  end

  it "parses this repo's own fragments and Unreleased section" do
    root = File.expand_path("../..", __dir__)
    repo = described_class.new(changelog_path: File.join(root, "CHANGELOG.md"), fragments_dir: File.join(root, "changelog.d"))
    expect(repo.entries).not_to be_empty
  end
end
