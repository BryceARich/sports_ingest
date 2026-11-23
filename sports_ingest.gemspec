# frozen_string_literal: true

require_relative "lib/sports_ingest/version"

Gem::Specification.new do |spec|
  spec.name = "sports_ingest"
  spec.version = SportsIngest::VERSION
  spec.authors = ["BryceARich"]

  spec.summary = "Read sports data (NHL, ESPN Fantasy, nflverse, licensed exports) into cached Ruby models."
  spec.description = <<~DESC
    sports_ingest reads sports data from public APIs, ESPN Fantasy, nflverse releases and
    manually exported licensed files, and turns it into clean, cached Ruby models that other
    projects consume. Each source loads separately and core has no native-extension dependencies.
  DESC
  spec.homepage = "https://github.com/BryceARich/sports_ingest"
  spec.required_ruby_version = ">= 4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Ship only library code and top-level docs; never specs, fixtures or anything else in git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z lib README.md CHANGELOG.md`.split("\x0")
  end
  spec.require_paths = ["lib"]

  # Core stays free of native extensions so it installs cleanly on a Raspberry Pi.
  spec.add_dependency "zeitwerk", "~> 2.6"
end
