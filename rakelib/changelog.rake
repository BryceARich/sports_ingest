# frozen_string_literal: true

require "date"
require_relative "lib/changelog"

changelog = RepoTools::Changelog.new(changelog_path: "CHANGELOG.md", fragments_dir: "changelog.d")

namespace :changelog do
  desc "Check that every changelog.d fragment parses"
  task :check do
    paths = changelog.fragment_paths
    changelog.entries
    puts "changelog: #{paths.size} fragment(s) OK"
  rescue RepoTools::Error => e
    abort "changelog: #{e.message}"
  end

  desc "Print the release section the fragments would make"
  task :preview, [:version, :date] do |_task, args|
    require_relative "../lib/sports_ingest/version"
    puts changelog.section(version: args[:version] || SportsIngest::VERSION, date: args[:date] || Date.today.iso8601)
  rescue RepoTools::Error => e
    abort "changelog: #{e.message}"
  end

  desc "Fold changelog.d fragments into CHANGELOG.md as a release (version defaults to the gem's) and delete them"
  task :compile, [:version, :date] do |_task, args|
    require_relative "../lib/sports_ingest/version"
    version = args[:version] || SportsIngest::VERSION
    deleted = changelog.compile!(version: version, date: args[:date] || Date.today.iso8601)
    puts "changelog: wrote [#{version}] from #{deleted.size} fragment(s)"
  rescue RepoTools::Error => e
    abort "changelog: #{e.message}"
  end
end
