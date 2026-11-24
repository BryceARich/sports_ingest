# frozen_string_literal: true

module SportsIngest
  module ESPN
    # Reserved for ESPN writes such as setting lineups (M4-08, ADR 0039). Nothing is implemented
    # yet, and the namespace is never loaded by +require "sports_ingest/espn"+: Zeitwerk loads it
    # only when code names +ESPN::Write+, so a caller has to ask for it explicitly.
    #
    # A write path gets its own client, not a flag on {Read::Client}, which only issues GETs
    # (see #32).
    module Write
    end
  end
end
