# frozen_string_literal: true

require "zeitwerk"

# Reads sports data from several sources and turns it into clean, cached Ruby models.
#
# +require "sports_ingest"+ loads core only. Each source has its own entry point
# (for example +require "sports_ingest/nhl"+) so that loading one source never loads another.
#
# Constants under +lib/sports_ingest/+ are autoloaded by Zeitwerk: one constant per file,
# with file paths matching constant names.
#
# @example
#   require "sports_ingest"
#   SportsIngest::VERSION # => "0.1.0"
module SportsIngest
  # The Zeitwerk loader for the gem's core.
  #
  # @return [Zeitwerk::Loader] the loader that autoloads +lib/sports_ingest/+
  # @example
  #   SportsIngest.loader.eager_load # load every core constant, e.g. to check file names
  def self.loader
    @loader
  end

  @loader = Zeitwerk::Loader.for_gem
  @loader.setup
end
