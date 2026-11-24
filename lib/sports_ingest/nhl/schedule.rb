# frozen_string_literal: true

require "date"

module SportsIngest
  module NHL
    # NHL games by date, date range, or team, as {Game} models (ADR 0017).
    #
    # - **By date or range:** reads +/schedule/{date}+, the whole league's week starting on that
    #   date, and follows +nextStartDate+ until the range is covered: one request per week.
    # - **One team, by date or range:** reads +/club-schedule/{TEAM}/week/{date}+ the same way,
    #   so only that team's games come over the wire. Its +nextStartDate+ skips the off-season.
    # - **One team, by month:** reads +/club-schedule/{TEAM}/month/{YYYY-MM}+.
    # - **One team, by season:** reads +/club-schedule-season/{TEAM}/{season}+, preseason and
    #   playoffs included.
    #
    # Dates are game dates, local to the venue. Games come back sorted by start time.
    #
    # A missing field raises {SourceChangedError}. A code the gem doesn't know (a new
    # +gameState+, say) doesn't: the game gets +:unknown+ or +:other+ and its raw code in
    # {Game#codes}, and the first time each such code turns up, a warning goes to +$stderr+.
    #
    # @example
    #   schedule = SportsIngest::NHL::Schedule.new
    #   schedule.on("2026-11-23").map { |g| "#{g.away_team.tri_code} @ #{g.home_team.tri_code}" }
    #   schedule.between("2026-11-23", "2026-11-30", team: "TOR").size
    #   schedule.for_team("TOR", month: "2026-11").size # => 13
    #   schedule.for_team("T.B", season: 2026).count { |g| g.game_type == :regular } # => 84 in 2026-27
    class Schedule
      # The first NHL season, by start year.
      FIRST_SEASON = 1917

      # A month, as +for_team(month:)+ takes it.
      MONTH = /\A\d{4}-(0[1-9]|1[0-2])\z/

      # Unknown codes already warned about, as +[field, code]+ pairs.
      WARNED = Set.new

      # @param client [Client, nil] what the NHL is read through; +nil+ means a new {Client}
      def initialize(client: nil)
        @client = client || Client.new
      end

      # Picks {#on}, {#between} or {#for_team} from the keywords; {NHL.schedule} calls this.
      #
      # @param date [Date, String, nil] one game date
      # @param from [Date, String, nil] first date of a range, with +to:+
      # @param to [Date, String, nil] last date of a range (inclusive), with +from:+
      # @param team [Team, String, nil] a {Team} or any code {Teams.fetch} knows; with +season:+
      #   or +month:+, or to narrow a date or range to that team
      # @param season [Integer, nil] the season's start year, with +team:+
      # @param month [Date, String, nil] a month as +YYYY-MM+ (or any Date in it), with +team:+
      # @return [Array<Game>]
      # @raise [ArgumentError] unless the keywords are exactly one of +date:+, +from:+ and +to:+,
      #   +season:+, or +month:+ (the last two need +team:+; the first two take it optionally)
      # @raise [NotFound] if +team+ matches no team
      # @raise [SourceChangedError, HTTPError, ParseError] as the methods it picks do
      def fetch(date: nil, from: nil, to: nil, team: nil, season: nil, month: nil)
        forms = {date: date, range: from || to, season: season, month: month}.compact.keys
        raise ArgumentError, "pass one of date:, from: and to:, season:, or month:; got #{forms.join(", ")}" if forms.size > 1

        case forms.first
        when :season, :month
          raise ArgumentError, "#{forms.first}: needs team:" if team.nil?

          for_team(team, season: season, month: month)
        when :date then on(date, team: team)
        when :range
          raise ArgumentError, "from: and to: go together" if from.nil? || to.nil?

          between(from, to, team: team)
        else
          raise ArgumentError, "pass date:, from: and to:, or team: with season: or month:"
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

      # Games from one date to another, both included. With +team:+ it reads that team's weekly
      # schedule instead of the whole league's.
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
        entries =
          if team
            weekly(from, to) { |day| "club-schedule/#{team.tri_code}/week/#{day.iso8601}" }
              .flat_map { |payload| club_games(payload) }
          else
            weekly(from, to) { |day| "schedule/#{day.iso8601}" }.flat_map { |payload| league_games(payload) }
          end
        entries = entries.select { |_game, date| Date.iso8601(date).between?(from, to) }
        finish(entries.map { |game, date| build(game, date) }, team)
      rescue KeyError, TypeError, NoMethodError, Date::Error => e
        raise SourceChangedError.new("NHL schedule isn't shaped as expected: #{e.message}", source: Client::SOURCE)
      end

      # One team's games for a season or a month, preseason and playoffs included.
      #
      # @param team [Team, String] a {Team} or any code {Teams.fetch} knows
      # @param season [Integer, nil] the season's start year (ADR 0006): +2026+ for 2026-27
      # @param month [Date, String, nil] +YYYY-MM+, or any Date in the month
      # @return [Array<Game>]
      # @raise [ArgumentError] unless exactly one of +season+ (an Integer from {FIRST_SEASON} on)
      #   and +month+ is given
      # @raise [NotFound] if +team+ matches no team, or the NHL has no such schedule
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      # @raise [HTTPError, ParseError] as {Client#get_json} does
      def for_team(team, season: nil, month: nil)
        raise ArgumentError, "pass season: or month:, not both" if season && month

        month = coerce_month(month) if month
        valid_season = season.is_a?(Integer) && season >= FIRST_SEASON
        unless month || valid_season
          raise ArgumentError, "season must be an Integer start year from #{FIRST_SEASON}, got #{season.inspect}"
        end

        team = resolve(team)
        raise ArgumentError, "team: is required" if team.nil?

        path = if month
          "club-schedule/#{team.tri_code}/month/#{month}"
        else
          "club-schedule-season/#{team.tri_code}/#{season}#{season + 1}"
        end
        finish(club_games(@client.get_json(path)).map { |game, date| build(game, date) }, nil)
      rescue KeyError, TypeError, NoMethodError => e
        raise SourceChangedError.new("NHL club schedule isn't shaped as expected: #{e.message}",
          source: Client::SOURCE)
      end

      # @return [String]
      def inspect
        "#<#{self.class.name}>"
      end

      private

      # Every week's payload from +from+ until +to+ is covered; the block gives each week's path.
      def weekly(from, to)
        payloads = []
        cursor = from
        while cursor <= to
          payload = @client.get_json(yield(cursor))
          payloads << payload
          following = payload["nextStartDate"] && Date.iso8601(payload["nextStartDate"])
          cursor = (following && following > cursor) ? following : cursor + 7
        end
        payloads
      end

      # +[game, date]+ pairs from a league week: games there carry no +gameDate+, their day does.
      def league_games(payload)
        payload.fetch("gameWeek").flat_map do |day|
          Array(day["games"]).map { |game| [game, day.fetch("date")] }
        end
      end

      # +[game, date]+ pairs from a club week, month or season.
      def club_games(payload)
        payload.fetch("games").map { |game| [game, game.fetch("gameDate")] }
      end

      def coerce_month(month)
        return month.strftime("%Y-%m") if month.is_a?(Date)
        return month if month.is_a?(String) && MONTH.match?(month)

        raise ArgumentError, "month must be YYYY-MM or a Date, got #{month.inspect}"
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
        codes = {game_type: game.fetch("gameType"), state: game.fetch("gameState"),
                 schedule_state: game.fetch("gameScheduleState"),
                 ended_in: game.dig("gameOutcome", "lastPeriodType")}.compact
        built = Game.new(
          id: game.fetch("id"),
          season: Integer(game.fetch("season").to_s[0, 4]),
          date: date,
          start_time: game.fetch("startTimeUTC"),
          venue: game.dig("venue", "default"),
          neutral_site: game.fetch("neutralSite", false),
          home_team: side(game.fetch("homeTeam")),
          away_team: side(game.fetch("awayTeam")),
          codes: codes,
          **codes.to_h { |field, code| [field, Game.from_code(field, code)] }
        )
        codes.each { |field, code| warn_unknown(field, code, built.id) }
        built
      rescue ArgumentError => e
        raise SourceChangedError.new("NHL game #{game["id"].inspect} isn't shaped as expected: #{e.message}",
          source: Client::SOURCE)
      end

      # Warns once per process for each field and code the gem doesn't know.
      def warn_unknown(field, code, game_id)
        return if Game.known_code?(field, code)

        key = [field, code]
        return if WARNED.include?(key)

        WARNED << key
        Kernel.warn("sports_ingest: NHL game #{game_id} has an unknown #{field} code #{code.inspect}; " \
          "it reads as #{Game.from_code(field, code).inspect} (see Game#codes)")
      end

      def side(team)
        {id: team.fetch("id"), tri_code: team.fetch("abbrev"), score: team["score"]}
      end
    end
  end
end
