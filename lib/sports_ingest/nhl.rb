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

    # Today's (or one day's) games with scores, state, period, clock, shots and power plays, in one request. See
    # {Scoreboard} for the details.
    #
    # @param date [Date, String, nil] the game date, +YYYY-MM-DD+; +nil+ means the NHL's current date
    # @param client [Client, nil] what the NHL is read through; +nil+ means a new {Client} that
    #   keeps scores fresh for {Scoreboard::TTL} seconds
    # @return [Array<GameScore>] sorted by start time
    # @raise [ArgumentError] if +date+ isn't a Date or +YYYY-MM-DD+
    # @raise [SourceChangedError] if the NHL's payload isn't shaped as expected
    # @raise [HTTPError, ParseError] if the request fails
    # @example
    #   SportsIngest::NHL.scores.select(&:live?).map(&:clock)
    #   SportsIngest::NHL.scores(date: "2026-11-22").count(&:final?)
    def self.scores(date: nil, client: nil)
      Scoreboard.new(client: client).on(date)
    end

    # One game's goals so far, from its play-by-play. See {GoalEvents}.
    #
    # @param game_id [Integer, String] the NHL game ID, all digits
    # @param client [Client, nil] what the NHL is read through; +nil+ means a new {Client} that
    #   keeps entries fresh for {Scoreboard::TTL} seconds
    # @return [Array<Goal>] in the NHL's order; empty before the first goal
    # @raise [ArgumentError] if +game_id+ isn't all digits
    # @raise [NotFound] if the NHL has no such game
    # @raise [SourceChangedError] if the payload isn't shaped as expected
    # @raise [HTTPError, ParseError] if the request fails
    # @example
    #   SportsIngest::NHL.goals(2026020378).map { |g| [g.period, g.time_in_period, g.strength] }
    def self.goals(game_id, client: nil)
      GoalEvents.new(client: client).fetch(game_id)
    end

    # The goals a poll found that the previous poll didn't. See {GoalEvents.new_since}.
    #
    # @param previous [Array<Goal>] the last poll's goals
    # @param current [Array<Goal>] this poll's goals
    # @return [Array<Goal>] the new ones, in +current+'s order
    # @raise [ArgumentError] if either isn't an Array of {Goal}s
    # @example
    #   SportsIngest::NHL.new_goals(previous: before, current: after)
    def self.new_goals(previous:, current:)
      GoalEvents.new_since(previous, current)
    end

    # One player's bio, draft, career and season totals. See {Players#fetch}.
    #
    # @param id [String, Integer] the NHL player ID
    # @return [PlayerDetails]
    # @raise [ArgumentError] if +id+ isn't all digits
    # @raise [NotFound] if the NHL has no such player
    # @raise [SourceChangedError] if the payload isn't shaped as expected
    # @raise [HTTPError, ParseError] if the request fails
    # @example
    #   SportsIngest::NHL.player(8478402).player.birth_date # => #<Date: 1997-01-13>
    def self.player(id)
      Players.new.fetch(id)
    end

    # One player's games in one season. See {Players#game_log}.
    #
    # @param id [String, Integer] the NHL player ID
    # @param season [Integer, nil] the season's start year; +nil+ for the NHL's current log
    # @param game_type [Symbol, nil] +:regular+ (the default with +season+) or +:playoffs+
    # @return [Array<GameLogEntry>] oldest first
    # @raise (see Players#game_log)
    # @example
    #   SportsIngest::NHL.game_log(8478402, season: 2025, game_type: :playoffs)
    def self.game_log(id, season: nil, game_type: nil)
      Players.new.game_log(id, season: season, game_type: game_type)
    end

    # Skater season totals, one row per player per season. See {SeasonStats#skaters}.
    #
    # @param seasons [Array<Integer>, nil] start years
    # @param last [Integer, nil] the N most recent seasons; +3+ when neither keyword is given
    # @param game_type [Symbol] +:regular+ or +:playoffs+
    # @return [Array<SeasonTotal>] by season, then player ID
    # @raise (see SeasonStats#skaters)
    # @example
    #   SportsIngest::NHL.skater_stats(last: 5).group_by(&:player_id)
    def self.skater_stats(seasons: nil, last: nil, game_type: :regular)
      SeasonStats.new.skaters(seasons: seasons, last: last, game_type: game_type)
    end

    # Goalie season totals, one row per player per season. See {SeasonStats#goalies}.
    #
    # @param (see .skater_stats)
    # @return (see .skater_stats)
    # @raise (see SeasonStats#goalies)
    # @example
    #   SportsIngest::NHL.goalie_stats(seasons: [2025], game_type: :playoffs)
    def self.goalie_stats(seasons: nil, last: nil, game_type: :regular)
      SeasonStats.new.goalies(seasons: seasons, last: last, game_type: game_type)
    end
  end
end
