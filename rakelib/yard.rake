# frozen_string_literal: true

require "open3"
require_relative "lib/doc_coverage"

namespace :yard do
  desc "Fail if YARD doc coverage is below #{RepoTools::DocCoverage::THRESHOLD}% (ADR 0015); lists what is undocumented"
  task :coverage, [:threshold] do |_task, args|
    output, status = Open3.capture2e("yard", "stats", "--list-undoc")
    puts output
    abort "yard: `yard stats` failed (exit #{status.exitstatus})" unless status.success?

    coverage = RepoTools::DocCoverage.new(output, threshold: args[:threshold] || RepoTools::DocCoverage::THRESHOLD)
    coverage.passing? ? puts(coverage.summary) : abort(coverage.summary)
  rescue RepoTools::Error => e
    abort "yard: #{e.message}"
  end
end
