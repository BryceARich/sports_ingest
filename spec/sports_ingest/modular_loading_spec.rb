# frozen_string_literal: true

require "open3"
require "rbconfig"

RSpec.describe "Modular loading" do
  source_modules = {
    "nhl" => "NHL",
    "espn" => "ESPN",
    "nflverse" => "Nflverse",
    "advanced_hockey" => "AdvancedHockey"
  }
  root = File.expand_path("../..", __dir__)

  # A fresh process, since this one may already have loaded other sources.
  loaded_after = lambda do |require_path|
    code = <<~RUBY
      require "#{require_path}"
      puts #{source_modules.values.inspect}.select { |m| SportsIngest.const_defined?(m, false) }.join(",")
      puts defined?(::CSV) || $LOADED_FEATURES.any? { |f| f.end_with?("/csv.rb") } ? "csv" : "no csv"
    RUBY
    out, err, status = Open3.capture3(RbConfig.ruby, "-rbundler/setup", "-Ilib", "-e", code, chdir: root)
    raise err unless status.success?

    out.lines(chomp: true)
  end

  it "covers every source in SportsIngest::SOURCES" do
    expect(source_modules.keys).to match_array(SportsIngest::SOURCES)
  end

  it "loads no source and no CSV on require \"sports_ingest\"" do
    expect(loaded_after.call("sports_ingest")).to eq(["", "no csv"])
  end

  source_modules.each do |source, mod|
    it "loads only #{mod} and no CSV on require \"sports_ingest/#{source}\"" do
      expect(loaded_after.call("sports_ingest/#{source}")).to eq([mod, "no csv"])
    end

    it "maps every file under lib/sports_ingest/#{source}/ to the constant its path names" do
      require "sports_ingest/#{source}"
      expect { SportsIngest.const_get(mod).loader.eager_load(force: true) }.not_to raise_error
    end
  end

  it "keeps core's dependencies free of native extensions" do
    names = Gem.loaded_specs.fetch("sports_ingest").runtime_dependencies.map(&:name)
    specs = {}
    while (name = names.shift)
      next if specs.key?(name)

      specs[name] = Gem.loaded_specs.fetch(name)
      names.concat(specs[name].runtime_dependencies.map(&:name))
    end
    expect(specs.values.reject { |spec| spec.extensions.empty? }.map(&:name)).to be_empty
  end
end
