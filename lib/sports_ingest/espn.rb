# frozen_string_literal: true

require_relative "../sports_ingest"

module SportsIngest
  # Reads ESPN Fantasy leagues (read-only). Built in M4.
  #
  # Load it with +require "sports_ingest/espn"+. Its code lives in +lib/sports_ingest/espn/+ and is
  # autoloaded by its own Zeitwerk loader, so requiring it loads no other source.
  #
  # @example
  #   require "sports_ingest/espn"
  #   SportsIngest::ESPN.loader # => #<Zeitwerk::Loader ...>
  module ESPN
    # The Zeitwerk loader for this source's folder.
    #
    # @return [Zeitwerk::Loader] the loader that autoloads +lib/sports_ingest/espn/+
    # @example
    #   SportsIngest::ESPN.loader.eager_load # load every constant in the source
    def self.loader
      @loader
    end

    @loader = SourceLoader.setup(self, "#{__dir__}/espn")
  end
end
