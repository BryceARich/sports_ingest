# frozen_string_literal: true

require "date"

module SportsIngest
  module ESPN
    # Every player's actual season totals from ESPN's player pool, as raw stat lines (ADR 0034).
    #
    # - **Endpoint:** +/seasons/{id}/players?view=kona_player_info+. Each player carries a +stats+
    #   array; the season total is the entry with +statSourceId+ 0 (actual), +statSplitTypeId+ 0
    #   and +scoringPeriodId+ 0. Projections (+statSourceId+ 1) and per-week rows are skipped.
    # - **Seasons:** +seasons: [2024, 2025]+ or +last: N+ (ADR 0006), +last: 3+ by default, counted
    #   back from {#current_season}. A season is named by its start year. ESPN names a hockey season
    #   by the year it ends (2026-27 is 2027) and a football season by the year it starts.
    # - **Errors:** ESPN answers 404 for a season it doesn't keep (hockey before about 2008, football
    #   before about 2005); that raises {NotFound} naming the season.
    # - **Filter:** +limit:+ sends +X-Fantasy-Filter+ (see {Filter.players}); without it ESPN's own
    #   default applies.
    # - **Cache:** each season is saved to the processed cache under
    #   +espn/player_stats/<game>/<ESPN season ID>/actual+ when +processed:+ is given.
    #
    # @example
    #   pool = SportsIngest::ESPN::PlayerPool.new(game: :hockey)
    #   pool.actual_stats(last: 3, limit: 500).select { it.season == 2026 }.map(&:full_name)
    class PlayerPool
      # The view that holds the player pool's stats.
      VIEW = "kona_player_info"

      # How many seasons +last:+ means when neither +seasons:+ nor +last:+ is given.
      DEFAULT_LAST = 3

      # Per game: how an ESPN season ID is derived from a start year, and the month a new season
      # becomes current (ADR 0034).
      RULES = {
        hockey: {id_offset: 1, rollover_month: 10},
        football: {id_offset: 0, rollover_month: 8}
      }.freeze

      # The season-total row's keys in ESPN's +stats+ array.
      SEASON_TOTAL = {"statSourceId" => 0, "statSplitTypeId" => 0, "scoringPeriodId" => 0}.freeze

      # @return [Symbol] +:hockey+ or +:football+
      attr_reader :game

      # @param game [Symbol] +:hockey+ or +:football+
      # @param client [Client, nil] what fetches from ESPN; +nil+ means a {Client} for +game+
      # @param processed [Cache::Processed, nil] where results are saved; +nil+ skips saving
      # @param today [Date, nil] the date {#current_season} judges by; +nil+ means today
      # @raise [ArgumentError] if +game+ isn't in {RULES}
      def initialize(game:, client: nil, processed: nil, today: nil)
        @game = game.to_sym
        raise ArgumentError, "game must be one of #{RULES.keys.join(", ")}, got #{game.inspect}" unless RULES.key?(@game)

        @client = client || Client.new(game: @game)
        @processed = processed
        @today = today
      end

      # Actual season totals for every player who has a line for each season.
      #
      # @param seasons [Array<Integer>, nil] start years
      # @param last [Integer, nil] the N most recent seasons; +3+ when neither keyword is given
      # @param limit [Integer, nil] at most this many players per season; +nil+ sends no filter
      # @return [Array<PlayerStats>] by season, oldest first; then in ESPN's order
      # @raise [ArgumentError] for bad +seasons+ / +last+ (see {Seasons.resolve}) or +limit+
      # @raise [NotFound] if ESPN keeps no data for a requested season
      # @raise [SourceChangedError] if a payload isn't shaped as expected
      # @raise [HTTPError, ParseError, AuthError] as {Client#get} does
      # @example
      #   SportsIngest::ESPN::PlayerPool.new(game: :football).actual_stats(seasons: [2025])
      def actual_stats(seasons: nil, last: nil, limit: nil)
        validate_limit(limit)
        years = Seasons.resolve(seasons: seasons, last: last, current: current_season,
          default_last: DEFAULT_LAST)
        years.flat_map { season_rows(it, limit) }
      end

      # The current season's start year on the pool's date. Hockey seasons start in October, football
      # in August (training camps), so the season that ended earlier still counts until then.
      #
      # @return [Integer] such as +2026+ for 2026-11-23 in hockey
      def current_season
        today = @today || Date.today
        (today.month >= RULES.fetch(game)[:rollover_month]) ? today.year : today.year - 1
      end

      # @param year [Integer] a season's start year
      # @return [Integer] ESPN's season ID for it, such as +2027+ for hockey 2026-27
      def espn_season_id(year)
        year + RULES.fetch(game)[:id_offset]
      end

      # @return [String] a summary without the client's cookies
      def inspect
        "#<#{self.class.name} game=#{game.inspect}>"
      end

      private

      def validate_limit(limit)
        return if limit.nil? || (limit.is_a?(Integer) && limit.positive?)

        raise ArgumentError, "limit must be a positive Integer or nil, got #{limit.inspect}"
      end

      def season_rows(year, limit)
        id = espn_season_id(year)
        response = fetch(year, id, limit)
        rows = parse_players(@client.parse(response), id, year)
        @processed&.write("espn/player_stats/#{game}/#{id}/actual", rows, source: Client::SOURCE,
          fetched_at: response.fetched_at, model: PlayerStats)
        rows
      end

      def fetch(year, id, limit)
        @client.get("seasons/#{id}/players", views: [VIEW], filter: limit && Filter.players(limit: limit))
      rescue NotFound
        raise NotFound.new("ESPN has no #{game} data for the #{year} season (ESPN season #{id}); it keeps " \
          "only recent seasons, so ask for fewer", source: Client::SOURCE)
      end

      def parse_players(payload, id, year)
        changed!("a player pool should be a JSON array, got #{payload.class}") unless payload.is_a?(Array)

        payload.filter_map { |player| player_row(player, id, year) }
      end

      def player_row(player, id, year)
        changed!("a player should be a JSON object, got #{player.class}") unless player.is_a?(Hash)
        entries = player["stats"]
        changed!("a player's \"stats\" should be an array, got #{entries.class}") unless entries.is_a?(Array)

        line = entries.find { season_total?(it, id) }
        return nil if line.nil? || line["stats"].to_h.empty?

        PlayerStats.new(player_id: player_id(player), full_name: player["fullName"],
          pro_team_id: player["proTeamId"], default_position_id: player["defaultPositionId"],
          game: game, season: year, stats: line_stats(line))
      end

      def season_total?(entry, id)
        entry.is_a?(Hash) && entry["seasonId"] == id && SEASON_TOTAL.all? { |key, value| entry[key] == value }
      end

      def player_id(player)
        id = player["id"]
        changed!("a player's \"id\" should be an Integer, got #{id.inspect}") unless id.is_a?(Integer)

        id
      end

      def line_stats(line)
        stats = line["stats"]
        changed!("a season total's \"stats\" should be an object, got #{stats.class}") unless stats.is_a?(Hash)

        stats
      end

      def changed!(message)
        raise SourceChangedError.new(message, source: Client::SOURCE)
      end
    end
  end
end
