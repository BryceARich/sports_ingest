# frozen_string_literal: true

require "open3"
require "rbconfig"

# Each source loads separately (ADR 0008). Isolation is checked in a fresh Ruby process, because
# this process may already have required other sources.
RSpec.describe "Modular loading" do
  # Every source's entry point and the module it defines. Add new sources here.
  source_modules = {
    "nhl" => "NHL",
    "espn" => "ESPN",
    "nflverse" => "Nflverse",
    "advanced_hockey" => "AdvancedHockey"
  }
  root = File.expand_path("../..", __dir__)

  # Runs +code+ in a fresh Ruby with the gem's bundle and returns its stdout lines.
  run_isolated = lambda do |code|
    out, err, status = Open3.capture3(
      RbConfig.ruby, "-rbundler/setup", "-I", File.join(root, "lib"), "-e", code, chdir: root
    )
    raise "isolated Ruby failed: #{err}" unless status.success?

    out.lines(chomp: true)
  end

  # Ruby snippet that prints which source modules and CSV are loaded.
  report = <<~RUBY
    puts #{source_modules.values.inspect}.select { |m| SportsIngest.const_defined?(m, false) }.join(",")
    puts defined?(::CSV) || $LOADED_FEATURES.any? { |f| f.end_with?("/csv.rb") } ? "csv" : "no csv"
  RUBY

  it "covers every source listed in SportsIngest::SOURCES" do
    expect(source_modules.keys).to match_array(SportsIngest::SOURCES)
  end

  it "loads no source and no CSV on require \"sports_ingest\"" do
    expect(run_isolated.call(%(require "sports_ingest"\n#{report}))).to eq(["", "no csv"])
  end

  source_modules.each do |source, mod|
    it "loads only #{mod} (and no CSV) on require \"sports_ingest/#{source}\"" do
      expect(run_isolated.call(%(require "sports_ingest/#{source}"\n#{report}))).to eq([mod, "no csv"])
    end

    it "maps every file under lib/sports_ingest/#{source}/ to the constant its path names" do
      require "sports_ingest/#{source}"
      expect { SportsIngest.const_get(mod).loader.eager_load(force: true) }.not_to raise_error
    end
  end

  it "keeps core free of native-extension dependencies" do
    pending_specs = Gem.loaded_specs.fetch("sports_ingest").runtime_dependencies.map(&:name)
    seen = {}
    until pending_specs.empty?
      name = pending_specs.shift
      next if seen.key?(name)

      spec = Gem.loaded_specs.fetch(name)
      seen[name] = spec.extensions
      pending_specs.concat(spec.runtime_dependencies.map(&:name))
    end
    expect(seen.reject { |_, extensions| extensions.empty? }).to be_empty
  end
end
