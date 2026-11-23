# frozen_string_literal: true

require_relative "../sports_ingest"

module SportsIngest
  # NHL public APIs.
  module NHL
    extend SourceLoader

    load_from "#{__dir__}/nhl"
  end
end
