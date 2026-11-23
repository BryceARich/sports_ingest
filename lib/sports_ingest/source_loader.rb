# frozen_string_literal: true

module SportsIngest
  # Builds the Zeitwerk loader that each source's entry point uses for its own folder.
  #
  # Core ignores every source (see {SportsIngest::SOURCES}), so a source's constants only
  # become loadable once its entry point (for example +require "sports_ingest/nhl"+) runs and
  # calls {.setup}. See ADR 0008.
  module SourceLoader
    # File-name inflections shared by every source loader, for acronyms Zeitwerk can't guess.
    #
    # @example
    #   SportsIngest::SourceLoader::INFLECTIONS["nhl"] # => "NHL"
    INFLECTIONS = {"nhl" => "NHL", "espn" => "ESPN"}.freeze

    # Sets up a loader that autoloads +dir+ into +namespace+.
    #
    # @param namespace [Module] the source's module, e.g. {SportsIngest::NHL}
    # @param dir [String] absolute path of the source's folder, e.g. +lib/sports_ingest/nhl+
    # @return [Zeitwerk::Loader] the loader, already set up
    # @raise [Zeitwerk::Error] if +dir+ doesn't exist or another loader already manages it
    # @example From lib/sports_ingest/nhl.rb
    #   module SportsIngest
    #     module NHL
    #       @loader = SourceLoader.setup(self, "#{__dir__}/nhl")
    #     end
    #   end
    def self.setup(namespace, dir)
      loader = Zeitwerk::Loader.new
      loader.tag = "sports_ingest/#{File.basename(dir)}"
      loader.inflector.inflect(INFLECTIONS)
      loader.push_dir(dir, namespace: namespace)
      loader.setup
      loader
    end
  end
end
