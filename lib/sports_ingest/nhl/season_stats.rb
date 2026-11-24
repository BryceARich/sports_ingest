# frozen_string_literal: true

require "json"

module SportsIngest
  module NHL
    # Skater and goalie season totals from the stats REST API's +skater/summary+ and
    # +goalie/summary+ tables (ADR 0024).
    #
    # - **Seasons:** +seasons: [2024, 2025]+ or +last: N+ (ADR 0006), +last: 3+ by default, counted
    #   back from {Season.current}.
    # - **Requests:** one table per season, 100 rows a page (the API's cap). A regular season is
    #   about 10 skater pages and 1-2 goalie pages, so +last: 5+ skaters is ~50 requests the first
    #   time; the raw cache serves repeats.
    # - **Cache:** each season is saved to the processed cache under
    #   +nhl/season_stats/<skaters|goalies>/<season ID>/<regular|playoffs>+ (read with
    #   +model: NHL::SeasonTotal+).
    #
    # @example
    #   stats = SportsIngest::NHL::SeasonStats.new
    #   stats.skaters(last: 3).select { it.player_id == "8478402" }.map { it.stats.points }
    #   stats.goalies(seasons: [2025], game_type: :playoffs)
    class SeasonStats
      # Game types a table can be asked for, and the NHL's code for each.
      GAME_TYPES = Players::GAME_TYPES

      # How many seasons +last:+ means when neither +seasons:+ nor +last:+ is given.
      DEFAULT_LAST = 3

      # Rows per page; the API returns at most 100 whatever +limit+ says.
      PAGE_SIZE = 100

      # Sort that keeps paging stable: the API's default order isn't.
      SORT = [{property: "playerId", direction: "ASC"}].to_json.freeze

      # Payload keys of a +skater/summary+ row, by {StatLine} field.
      SKATER_KEYS = {
        games_played: "gamesPlayed", goals: "goals", assists: "assists", points: "points",
        plus_minus: "plusMinus", pim: "penaltyMinutes", shots: "shots", shooting_pct: "shootingPct",
        power_play_goals: "ppGoals", power_play_points: "ppPoints", shorthanded_goals: "shGoals",
        shorthanded_points: "shPoints", game_winning_goals: "gameWinningGoals", ot_goals: "otGoals",
        faceoff_pct: "faceoffWinPct"
      }.freeze

      # Payload keys of a +goalie/summary+ row, by {StatLine} field.
      GOALIE_KEYS = {
        games_played: "gamesPlayed", goals: "goals", assists: "assists", points: "points",
        pim: "penaltyMinutes", games_started: "gamesStarted", wins: "wins", losses: "losses",
        ot_losses: "otLosses", shutouts: "shutouts", goals_against: "goalsAgainst",
        shots_against: "shotsAgainst", goals_against_avg: "goalsAgainstAverage", save_pct: "savePct",
        toi_seconds: "timeOnIce"
      }.freeze

      # @param client [Client] what fetches from the NHL
      # @param processed [Cache::Processed, nil] where results are saved; +nil+ skips saving
      # @param today [Date, nil] the date {Season.current} judges by; +nil+ means today
      def initialize(client: Client.new, processed: Cache::Processed.new, today: nil)
        @client = client
        @processed = processed
        @today = today
      end

      # Skater totals, one row per player per season.
      #
      # @param seasons [Array<Integer>, nil] start years
      # @param last [Integer, nil] the N most recent seasons; +3+ when neither keyword is given
      # @param game_type [Symbol] +:regular+ or +:playoffs+
      # @return [Array<SeasonTotal>] by season, then player ID
      # @raise [ArgumentError] for bad +seasons+ / +last+ (see {Seasons.resolve}) or +game_type+
      # @raise [SourceChangedError] if a payload isn't shaped as expected
      # @raise [HTTPError, ParseError] as {Client#stats_json} does
      def skaters(seasons: nil, last: nil, game_type: :regular)
        table(:skaters, seasons, last, game_type)
      end

      # Goalie totals, one row per player per season.
      #
      # @param (see #skaters)
      # @return (see #skaters)
      # @raise (see #skaters)
      def goalies(seasons: nil, last: nil, game_type: :regular)
        table(:goalies, seasons, last, game_type)
      end

      # Maps one page of a +skater/summary+ or +goalie/summary+ payload to rows.
      #
      # @param payload [Hash] the parsed JSON
      # @param kind [Symbol] +:skaters+ or +:goalies+
      # @param game_type [Symbol] the game type the page was asked for
      # @return [Array<SeasonTotal>]
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      def parse_page(payload, kind:, game_type:)
        data(payload).map { row(it, kind, game_type) }
      end

      # @return [String]
      def inspect
        "#<#{self.class.name}>"
      end

      private

      def table(kind, seasons, last, game_type)
        code = GAME_TYPES.fetch(game_type) do
          raise ArgumentError, "game_type must be one of #{GAME_TYPES.keys.join(", ")}, got #{game_type.inspect}"
        end
        years = Seasons.resolve(seasons: seasons, last: last, current: Season.current(@today || Date.today),
          default_last: DEFAULT_LAST)
        years.flat_map { season_table(kind, it, game_type, code) }
      end

      def season_table(kind, year, game_type, code)
        path = "#{(kind == :skaters) ? "skater" : "goalie"}/summary"
        filter = "seasonId=#{Season.id(year)} and gameTypeId=#{code}"
        rows = []
        fetched_at = nil
        loop do
          response = @client.get(@client.url_for(path, base: Client::STATS_URL),
            params: {cayenneExp: filter, sort: SORT, start: rows.size, limit: PAGE_SIZE})
          fetched_at ||= response.fetched_at
          payload = @client.parse(response)
          page = parse_page(payload, kind: kind, game_type: game_type)
          rows.concat(page)
          break if page.empty? || rows.size >= total(payload)
        end
        rows.sort_by! { it.player_id.to_i }
        @processed&.write("nhl/season_stats/#{kind}/#{Season.id(year)}/#{game_type}", rows,
          source: Client::SOURCE, fetched_at: fetched_at, model: SeasonTotal)
        rows
      end

      def row(row, kind, game_type)
        changed!("a stats row should be an object, got #{row.class}") unless row.is_a?(Hash)

        goalie = kind == :goalies
        keys = goalie ? GOALIE_KEYS : SKATER_KEYS
        stats = keys.to_h { |field, key| [field, row[key]] }
        stats[:avg_toi_seconds] = row["timeOnIcePerGame"]&.round unless goalie
        SeasonTotal.new(
          player_id: row["playerId"], full_name: row[goalie ? "goalieFullName" : "skaterFullName"],
          position: goalie ? "G" : row["positionCode"], teams: row["teamAbbrevs"].to_s.split(","),
          stats: StatLine.new(season: Season.year(row["seasonId"]), game_type: game_type, league: "NHL", **stats)
        )
      rescue ArgumentError => e
        changed!("stats row for player #{row["playerId"].inspect} doesn't fit the SeasonTotal model: #{e.message}")
      end

      def data(payload)
        changed!("a stats table should be a JSON object, got #{payload.class}") unless payload.is_a?(Hash)
        rows = payload["data"]
        changed!("a stats table's \"data\" should be an array, got #{rows.class}") unless rows.is_a?(Array)

        rows
      end

      def total(payload)
        total = payload["total"]
        changed!("a stats table's \"total\" should be an Integer, got #{total.inspect}") unless total.is_a?(Integer)

        total
      end

      def changed!(message)
        raise SourceChangedError.new(message, source: Client::SOURCE)
      end
    end
  end
end
