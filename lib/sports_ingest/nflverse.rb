# frozen_string_literal: true

require_relative "../sports_ingest"

module SportsIngest
  # nflverse release files.
  module Nflverse
    extend SourceLoader

    load_from "#{__dir__}/nflverse"
  end
end
