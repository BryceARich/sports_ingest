# frozen_string_literal: true

namespace :fixtures do
  desc "Re-record VCR cassettes against the live sources (needs the network; ADR 0013). " \
    "Optional spec path, e.g. rake fixtures:record[spec/sports_ingest/nhl]"
  task :record, [:path] do |_task, args|
    abort "fixtures:record: CI only replays cassettes; record on your own machine" unless ENV["CI"].to_s.empty?

    mode = ENV.fetch("SPORTS_INGEST_RECORD", "all")
    command = ["rspec", "--tag", "vcr", args[:path] || "spec"]
    puts "Recording (#{mode}): #{command.join(" ")}"
    system({"SPORTS_INGEST_RECORD" => mode}, *command) || abort("fixtures:record: rspec failed")
    puts "Check the diff in spec/fixtures/cassettes before committing; secrets and cookies are scrubbed, " \
      "but read what changed."
  end
end
