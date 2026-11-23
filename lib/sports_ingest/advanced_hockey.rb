# frozen_string_literal: true

require_relative "../sports_ingest"

module SportsIngest
  # Reads manually exported, licensed Evolving-Hockey and PuckPedia files. Built in M6.
  #
  # Load it with +require "sports_ingest/advanced_hockey"+. Its code lives in +lib/sports_ingest/advanced_hockey/+ and is
  # autoloaded by its own Zeitwerk loader, so requiring it loads no other source.
  #
  # @example
  #   require "sports_ingest/advanced_hockey"
  #   SportsIngest::AdvancedHockey.loader # => #<Zeitwerk::Loader ...>
  module AdvancedHockey
    # The Zeitwerk loader for this source's folder.
    #
    # @return [Zeitwerk::Loader] the loader that autoloads +lib/sports_ingest/advanced_hockey/+
    # @example
    #   SportsIngest::AdvancedHockey.loader.eager_load # load every constant in the source
    def self.loader
      @loader
    end

    @loader = SourceLoader.setup(self, "#{__dir__}/advanced_hockey")
  end
end
