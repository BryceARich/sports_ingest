# frozen_string_literal: true

require "json"
require "uri"

module SportsIngest
  module ESPN
    module Read
      # Reads the ESPN Fantasy API for one game (hockey or football), read-only
      # (ADR 0032 in +docs/adr/0032-espn-client-and-cookies.md+).
      #
      # - **URLs:** +https://lm-api-reads.fantasy.espn.com/apis/v3/games/{fhl|ffl}/<path>+.
      # - **Views:** +views:+ become repeated +view=+ query parameters, in the order given.
      # - **Filter:** +filter:+ (a {Filter} or a Hash) is sent as the +X-Fantasy-Filter+ header.
      # - **Cookies:** when both {Configuration#espn_s2} and {Configuration#espn_swid} are set, every
      #   request sends them as a +Cookie+ header, held as a {Secret} so it's revealed only on the
      #   wire. Public leagues work without them; a private league without them raises {AuthError}.
      # - **Caching:** requests go through {Cache::Raw} with the +:espn+ TTL unless +http:+ is given.
      #
      # @example A private league's settings and teams
      #   espn = SportsIngest::ESPN::Read::Client.new(game: :hockey)
      #   league = espn.league(12_345, season: 2027, views: %w[mSettings mTeam])
      #   league["settings"]["name"]
      class Client
        # The host every request goes to.
        HOST = "lm-api-reads.fantasy.espn.com"

        # Everything before the game segment.
        BASE_URL = "https://#{HOST}/apis/v3/games"

        # Game names accepted by +game:+, mapped to ESPN's segment.
        GAMES = {hockey: "fhl", fhl: "fhl", football: "ffl", ffl: "ffl"}.freeze

        # The source recorded on errors and used for the cache TTL.
        SOURCE = :espn

        # @return [String] ESPN's game segment, +"fhl"+ or +"ffl"+
        attr_reader :game

        # @param game [Symbol, String] +:hockey+ / +:fhl+ or +:football+ / +:ffl+
        # @param http [#get, nil] what requests go through; +nil+ means a {Cache::Raw} around an
        #   {HTTP::Client} for +:espn+
        # @param configuration [Configuration, nil] settings to read the cookies from; +nil+ means
        #   {SportsIngest.configuration} at request time
        # @raise [ArgumentError] if +game+ isn't one of {GAMES}
        def initialize(game:, http: nil, configuration: nil)
          @game = GAMES.fetch(game.to_s.downcase.to_sym) do
            raise ArgumentError, "game must be one of #{GAMES.keys.join(", ")}, got #{game.inspect}"
          end
          @configuration = configuration
          @http = http || Cache::Raw.new(client: HTTP::Client.new(source: SOURCE, configuration: configuration),
            configuration: configuration)
        end

        # Game metadata for a season: its name, dates and current scoring period.
        #
        # @param year [Integer] ESPN's season ID: the year a hockey season ends, the year a football
        #   season starts
        # @return [Hash] the parsed JSON
        # @raise [ArgumentError] if +year+ isn't a positive Integer
        # @raise [NotFound, HTTPError, ParseError] as {#get_json} does
        # @example
        #   SportsIngest::ESPN::Read::Client.new(game: :hockey).season(2027)["currentScoringPeriod"]
        def season(year)
          get_json("seasons/#{positive_integer(year, "year")}")
        end

        # A league for one season, shaped by +views+.
        #
        # @param league_id [Integer] the ID in the league's URL (+leagueId=+)
        # @param season [Integer] ESPN's season ID, as in {#season}
        # @param views [Array<String>] +view=+ values, such as +mSettings+ or +mTeam+
        # @param filter [Filter, Hash, nil] the +X-Fantasy-Filter+ header
        # @return [Hash] the parsed JSON
        # @raise [ArgumentError] if +league_id+ or +season+ isn't a positive Integer
        # @raise [AuthError] if the league is private and the cookies are missing or rejected
        # @raise [NotFound] if there's no such league
        # @raise [HTTPError, ParseError] as {#get_json} does
        # @example
        #   espn.league(12_345, season: 2027, views: ["mTeam"])["teams"]
        def league(league_id, season:, views: [], filter: nil)
          path = "seasons/#{positive_integer(season, "season")}/segments/0/leagues/" \
            "#{positive_integer(league_id, "league_id")}"
          get_json(path, views: views, filter: filter)
        end

        # Fetches a path under this game and parses the JSON body.
        #
        # @param path [String] the path after +/games/{game}/+, e.g. +"seasons/2027/players"+
        # @param views [Array<String>] +view=+ values
        # @param params [Hash{#to_s => #to_s}] other query parameters
        # @param filter [Filter, Hash, nil] the +X-Fantasy-Filter+ header
        # @return [Hash, Array] the parsed JSON
        # @raise [AuthError, NotFound, HTTPError] as {#get} does
        # @raise [ParseError] if the body isn't JSON
        # @example
        #   espn.get_json("seasons/2027/players", views: ["kona_player_info"],
        #     filter: SportsIngest::ESPN::Read::Filter.players(limit: 50))
        def get_json(path, views: [], params: {}, filter: nil)
          parse(get(path, views: views, params: params, filter: filter))
        end

        # Fetches a path under this game. Use it over {#get_json} when you need the response's
        # +fetched_at+ or +stale+.
        #
        # @param path [String] the path after +/games/{game}/+
        # @param views [Array<String>] +view=+ values
        # @param params [Hash{#to_s => #to_s}] other query parameters
        # @param filter [Filter, Hash, nil] the +X-Fantasy-Filter+ header
        # @return [HTTP::Response] the response, possibly from the raw cache
        # @raise [AuthError] on 401 or 403, with a hint about the cookies
        # @raise [NotFound] on 404
        # @raise [HTTPError] on any other failure, as {HTTP::Client#get} does
        # @example
        #   espn.get("seasons/2027").fetched_at
        def get(path, views: [], params: {}, filter: nil)
          url = url_for(path, views)
          @http.get(url, params: params, headers: headers_for(filter))
        rescue AuthError => e
          raise AuthError.new("#{e.message}: #{auth_hint}", source: SOURCE)
        end

        # Builds the URL for a path under this game, with +views+ as repeated +view=+ parameters.
        #
        # @param path [String] the path after +/games/{game}/+
        # @param views [Array<String>] +view=+ values
        # @return [String] the URL
        # @example
        #   SportsIngest::ESPN::Read::Client.new(game: :ffl).url_for("seasons/2026", ["mTeam", "mRoster"])
        #   # => "https://lm-api-reads.fantasy.espn.com/apis/v3/games/ffl/seasons/2026?view=mTeam&view=mRoster"
        def url_for(path, views = [])
          url = "#{BASE_URL}/#{game}/#{path.to_s.delete_prefix("/")}"
          views = Array(views)
          views.empty? ? url : "#{url}?#{URI.encode_www_form(views.map { |view| ["view", view.to_s] })}"
        end

        # Parses a response body as JSON.
        #
        # @param response [HTTP::Response] a response from {#get}
        # @return [Hash, Array] the parsed JSON
        # @raise [ParseError] if the body isn't JSON
        def parse(response)
          JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise ParseError.new("ESPN sent a body that isn't JSON from #{response.url}: #{e.message[0, 100]}",
            source: SOURCE)
        end

        # @return [String] a summary that never includes the cookies
        def inspect
          "#<#{self.class.name} game=#{game.inspect} cookies=#{credentials? ? Secret::REDACTED : "none"}>"
        end

        private

        def configuration
          @configuration || SportsIngest.configuration
        end

        def credentials?
          configuration.espn_credentials?
        end

        def headers_for(filter)
          headers = {}
          headers["X-Fantasy-Filter"] = Filter.wrap(filter).to_header unless filter.nil?
          headers["Cookie"] = cookie if credentials?
          headers
        end

        def cookie
          Secret.new("espn_s2=#{configuration.espn_s2.reveal}; SWID=#{configuration.espn_swid.reveal}")
        end

        def auth_hint
          if credentials?
            "ESPN rejected the espn_s2 / SWID cookies; they may have expired, so copy fresh ones " \
              "from a logged-in browser"
          else
            missing = {"espn_s2" => configuration.espn_s2, "SWID" => configuration.espn_swid}
              .select { |_name, value| value.nil? }.keys
            "private leagues need the espn_s2 and SWID cookies (missing: #{missing.join(", ")}); set " \
              "SPORTS_INGEST_ESPN_S2 and SPORTS_INGEST_ESPN_SWID or SportsIngest.configure"
          end
        end

        def positive_integer(value, name)
          return value if value.is_a?(Integer) && value.positive?

          raise ArgumentError, "#{name} must be a positive Integer, got #{value.inspect}"
        end
      end
    end
  end
end
