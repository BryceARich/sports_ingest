# frozen_string_literal: true

require_relative "../sports_ingest"

module SportsIngest
  # ESPN Fantasy leagues.
  module ESPN
    extend SourceLoader

    load_from "#{__dir__}/espn"
  end
end
