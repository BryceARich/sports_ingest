# frozen_string_literal: true

require_relative "../sports_ingest"

module SportsIngest
  # NHL public APIs.
  module NHL
    extend SourceLoader

    load_from "#{__dir__}/nhl"

    # NHL games by date, date range, or team and season or month. See {Schedule} for the details.
    #
    # @param date [Date, String, nil] one game date, +YYYY-MM-DD+
    # @param from [Date, String, nil] first date of a range, with +to:+
    # @param to [Date, String, nil] last date of a range (inclusive), with +from:+
    # @param team [Team, String, nil] a team code or {Team}; with +season:+ or +month:+, or to
    #   narrow a date or range to that team
    # @param season [Integer, nil] the season's start year, with +team:+
    # @param month [Date, String, nil] +YYYY-MM+, with +team:+
    # @param client [Client, nil] what the NHL is read through; +nil+ means a new {Client}
    # @return [Array<Game>] sorted by start time
    # @raise [ArgumentError] for a combination of keywords {Schedule#fetch} doesn't take
    # @raise [NotFound] if +team+ matches no team
    # @raise [SourceChangedError] if the NHL's payload isn't shaped as expected
    # @raise [HTTPError, ParseError] if the request fails
    # @example
    #   SportsIngest::NHL.schedule(date: "2026-11-23")
    #   SportsIngest::NHL.schedule(from: "2026-11-23", to: "2026-11-30", team: "TOR")
    #   SportsIngest::NHL.schedule(team: "TOR", month: "2026-11")
    #   SportsIngest::NHL.schedule(team: "TOR", season: 2026)
    def self.schedule(date: nil, from: nil, to: nil, team: nil, season: nil, month: nil, client: nil)
      Schedule.new(client: client).fetch(date: date, from: from, to: to, team: team, season: season, month: month)
    end
  end
end
