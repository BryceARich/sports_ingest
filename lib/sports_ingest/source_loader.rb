# frozen_string_literal: true

module SportsIngest
  # Gives a source module its own Zeitwerk loader (ADR 0008).
  module SourceLoader
    # Acronyms in source file names.
    INFLECTIONS = {"nhl" => "NHL", "espn" => "ESPN"}.freeze

    # @return [Zeitwerk::Loader] the source's loader
    attr_reader :loader

    # Autoloads +dir+ into this module.
    #
    # @param dir [String] the source's folder
    # @return [Zeitwerk::Loader]
    # @raise [Zeitwerk::Error] if +dir+ doesn't exist or is already managed
    def load_from(dir)
      @loader = Zeitwerk::Loader.new.tap do |loader|
        loader.tag = "sports_ingest/#{File.basename(dir)}"
        loader.inflector.inflect(INFLECTIONS)
        loader.push_dir(dir, namespace: self)
        loader.setup
      end
    end
  end
end
