# frozen_string_literal: true

require_relative "../sports_ingest"

module SportsIngest
  # Evolving-Hockey and PuckPedia exports.
  module AdvancedHockey
    extend SourceLoader

    # The +source+ on errors this module raises.
    SOURCE = :advanced_hockey

    load_from "#{__dir__}/advanced_hockey"
  end
end
