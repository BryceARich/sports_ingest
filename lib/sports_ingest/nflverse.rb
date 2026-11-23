# frozen_string_literal: true

require_relative "../sports_ingest"

module SportsIngest
  # Reads nflverse release files from GitHub. Built in M5.
  #
  # Load it with +require "sports_ingest/nflverse"+. Its code lives in +lib/sports_ingest/nflverse/+ and is
  # autoloaded by its own Zeitwerk loader, so requiring it loads no other source.
  #
  # @example
  #   require "sports_ingest/nflverse"
  #   SportsIngest::Nflverse.loader # => #<Zeitwerk::Loader ...>
  module Nflverse
    # The Zeitwerk loader for this source's folder.
    #
    # @return [Zeitwerk::Loader] the loader that autoloads +lib/sports_ingest/nflverse/+
    # @example
    #   SportsIngest::Nflverse.loader.eager_load # load every constant in the source
    def self.loader
      @loader
    end

    @loader = SourceLoader.setup(self, "#{__dir__}/nflverse")
  end
end
