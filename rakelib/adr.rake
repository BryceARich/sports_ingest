# frozen_string_literal: true

require_relative "lib/adr_index"

adr_index = RepoTools::AdrIndex.new("docs/adr")

namespace :adr do
  desc "Rewrite the index table in docs/adr/README.md from the ADR files (run at release)"
  task :index do
    puts(adr_index.write! ? "adr: index updated" : "adr: index already up to date")
  rescue RepoTools::Error => e
    abort "adr: #{e.message}"
  end

  desc "Fail if a row in the ADR index is wrong; list ADRs waiting for the next release's index"
  task :check do
    problems = adr_index.problems
    abort "adr: index is wrong; run `rake adr:index`\n#{problems.join("\n")}" if problems.any?

    waiting = adr_index.unindexed
    puts "adr: index OK" + (waiting.empty? ? "" : "; added at the next release: #{waiting.map(&:file).join(", ")}")
  rescue RepoTools::Error => e
    abort "adr: #{e.message}"
  end
end

namespace :release do
  desc "Prepare a release: compile the changelog fragments and rewrite the ADR index"
  task :prepare, [:version, :date] => ["changelog:compile", "adr:index"]
end
