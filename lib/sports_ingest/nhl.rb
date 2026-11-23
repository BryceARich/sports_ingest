# frozen_string_literal: true

require_relative "../sports_ingest"

module SportsIngest
  # Reads the public NHL APIs (+api-web.nhle.com+ and +api.nhle.com/stats/rest+). Built in M2.
  #
  # Load it with +require "sports_ingest/nhl"+. Its code lives in +lib/sports_ingest/nhl/+ and is
  # autoloaded by its own Zeitwerk loader, so requiring it loads no other source.
  #
  # @example
  #   require "sports_ingest/nhl"
  #   SportsIngest::NHL.loader # => #<Zeitwerk::Loader ...>
  module NHL
    # The Zeitwerk loader for this source's folder.
    #
    # @return [Zeitwerk::Loader] the loader that autoloads +lib/sports_ingest/nhl/+
    # @example
    #   SportsIngest::NHL.loader.eager_load # load every constant in the source
    def self.loader
      @loader
    end

    @loader = SourceLoader.setup(self, "#{__dir__}/nhl")
  end
end
