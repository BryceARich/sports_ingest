# frozen_string_literal: true

require "date"

module SportsIngest
  module NHL
    # NHL games by date, date range, or team and season, as {Game} models (ADR 0017).
    #
    # - **By date or range:** reads +/schedule/{date}+, which returns the week starting on that
    #   date, and follows +nextStartDate+ until the range is covered: one request per week.
    # - **By team and season:** reads +/club-schedule-season/{TEAM}/{season}+, preseason included.
    # - **Team filter:** +team:+ with a date or range keeps only that team's games.
    #
    # Dates are game dates, local to the venue. Games come back sorted by start time.
    #
    # @example
    #   schedule = SportsIngest::NHL::Schedule.new
    #   schedule.on("2026-11-23").map { |g| "#{g.away_team.tri_code} @ #{g.home_team.tri_code}" }
    #   schedule.between("2026-11-23", "2026-11-30", team: "TOR").size
    #   schedule.for_team("T.B", season: 2026).count { |g| g.game_type == :regular } # => 84 in 2026-27
    class Schedule
      # The first NHL season, by start year.
      FIRST_SEASON = 1917

      # @param client [Client, nil] what the NHL is read through; +nil+ means a new {Client}
      def initialize(client: nil)
        @client = client || Client.new
      end

      # Picks {#on}, {#between} or {#for_team} from the keywords; {NHL.schedule} calls this.
      #
      # @param date [Date, String, nil] one game date
      # @param from [Date, String, nil] first date of a range, with +to:+
      # @param to [Date, String, nil] last date of a range (inclusive), with +from:+
      # @param team [Team, String, nil] a {Team} or any code {Teams.fetch} knows; alone with
      #   +season:+, or filtering a date or range
      # @param season [Integer, nil] the season's start year, with +team:+
      # @return [Array<Game>]
      # @raise [ArgumentError] unless the keywords are exactly one of +date:+, +from:+ and +to:+,
      #   or +team:+ and +season:+ (+team:+ may filter either date form)
      # @raise [NotFound] if +team+ matches no team
      # @raise [SourceChangedError, HTTPError, ParseError] as the methods it picks do
      def fetch(date: nil, from: nil, to: nil, team: nil, season: nil)
        if !season.nil?
          raise ArgumentError, "season: needs team: and can't be combined with dates" if team.nil? || date || from || to

          for_team(team, season: season)
        elsif !date.nil?
          raise ArgumentError, "pass date: or from:/to:, not both" if from || to

          on(date, team: team)
        elsif from || to
          raise ArgumentError, "from: and to: go together" if from.nil? || to.nil?

          between(from, to, team: team)
        else
          raise ArgumentError, "pass date:, from: and to:, or team: and season:"
        end
      end

      # Games on one date.
      #
      # @param date [Date, String] the game date, or +YYYY-MM-DD+
      # @param team [Team, String, nil] only this team's games
      # @return [Array<Game>]
      # @raise [ArgumentError] if +date+ isn't a Date or +YYYY-MM-DD+
      # @raise [NotFound] if +team+ matches no team
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      # @raise [HTTPError, ParseError] as {Client#get_json} does
      def on(date, team: nil)
        date = Game.coerce_date(date)
        between(date, date, team: team)
      end

      # Games from one date to another, both included.
      #
      # @param from [Date, String] the first date
      # @param to [Date, String] the last date
      # @param team [Team, String, nil] only this team's games
      # @return [Array<Game>]
      # @raise [ArgumentError] if a date is invalid or +from+ is after +to+
      # @raise [NotFound] if +team+ matches no team
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      # @raise [HTTPError, ParseError] as {Client#get_json} does
      def between(from, to, team: nil)
        from = Game.coerce_date(from)
        to = Game.coerce_date(to)
        raise ArgumentError, "from (#{from}) is after to (#{to})" if from > to

        team = resolve(team)
        games = weeks(from, to).flat_map do |day|
          day_date = Date.iso8601(day.fetch("date"))
          next [] unless day_date.between?(from, to)

          Array(day["games"]).map { |game| build(game, day_date) }
        end
        finish(games, team)
      rescue KeyError, TypeError, Date::Error => e
        raise SourceChangedError.new("NHL schedule isn't shaped as expected: #{e.message}", source: Client::SOURCE)
      end

      # One team's games for a season, preseason and playoffs included.
      #
      # @param team [Team, String] a {Team} or any code {Teams.fetch} knows
      # @param season [Integer] the season's start year (ADR 0006): +2026+ for 2026-27
      # @return [Array<Game>]
      # @raise [ArgumentError] if +season+ isn't an Integer from {FIRST_SEASON} on
      # @raise [NotFound] if +team+ matches no team, or the NHL has no such schedule
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      # @raise [HTTPError, ParseError] as {Client#get_json} does
      def for_team(team, season:)
        unless season.is_a?(Integer) && season >= FIRST_SEASON
          raise ArgumentError, "season must be an Integer start year from #{FIRST_SEASON}, got #{season.inspect}"
        end

        team = resolve(team)
        raise ArgumentError, "team: is required" if team.nil?

        payload = @client.get_json("club-schedule-season/#{team.tri_code}/#{season}#{season + 1}")
        games = payload.fetch("games").map { |game| build(game, game.fetch("gameDate")) }
        finish(games, nil)
      rescue KeyError, TypeError, NoMethodError => e
        raise SourceChangedError.new("NHL club schedule isn't shaped as expected: #{e.message}",
          source: Client::SOURCE)
      end

      # @return [String]
      def inspect
        "#<#{self.class.name}>"
      end

      private

      # Each day of every week that overlaps from..to.
      def weeks(from, to)
        days = []
        cursor = from
        while cursor <= to
          payload = @client.get_json("schedule/#{cursor.iso8601}")
          days.concat(payload.fetch("gameWeek"))
          following = payload["nextStartDate"] && Date.iso8601(payload["nextStartDate"])
          cursor = (following && following > cursor) ? following : cursor + 7
        end
        days
      end

      def resolve(team)
        case team
        when nil, Team then team
        else Teams.fetch(team)
        end
      end

      def finish(games, team)
        games = games.select { |game| game.involves?(team) } if team
        games.sort_by { |game| [game.start_time, game.id] }
      end

      def build(game, date)
        Game.new(
          id: game.fetch("id"),
          season: Integer(game.fetch("season").to_s[0, 4]),
          game_type: Game::GAME_TYPES.fetch(game.fetch("gameType")),
          date: date,
          start_time: game.fetch("startTimeUTC"),
          state: Game::STATES.fetch(game.fetch("gameState")),
          schedule_state: Game::SCHEDULE_STATES.fetch(game.fetch("gameScheduleState")),
          ended_in: game.dig("gameOutcome", "lastPeriodType")&.then { |type| Game::PERIOD_TYPES.fetch(type) },
          venue: game.dig("venue", "default"),
          neutral_site: game.fetch("neutralSite", false),
          home_team: side(game.fetch("homeTeam")),
          away_team: side(game.fetch("awayTeam"))
        )
      rescue ArgumentError => e
        raise SourceChangedError.new("NHL game #{game["id"].inspect} isn't shaped as expected: #{e.message}",
          source: Client::SOURCE)
      end

      def side(team)
        {id: team.fetch("id"), tri_code: team.fetch("abbrev"), score: team["score"]}
      end
    end
  end
end
