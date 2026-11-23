# frozen_string_literal: true

require "json"

module SportsIngest
  module NHL
    # Reads the NHL's two public hosts. No auth. Endpoints and quirks are in
    # +docs/sources/nhl.md+.
    #
    # - **Web API:** +https://api-web.nhle.com/v1/<path>+, through {#get_json}.
    # - **Stats REST API:** +https://api.nhle.com/stats/rest/en/<path>+, through {#stats_json}.
    # - **Caching:** requests go through {Cache::Raw} with the +:nhl+ TTL unless +http:+ is given.
    # - **Errors:** 404 raises {NotFound}, a body that isn't JSON {ParseError}; the rest come from
    #   {HTTP::Client#get}.
    #
    # @example
    #   nhl = SportsIngest::NHL::Client.new
    #   nhl.get_json("schedule/2026-11-23")["gameWeek"]
    #   nhl.stats_json("skater/summary", params: {limit: 5, cayenneExp: "seasonId=20262027 and gameTypeId=2"})
    class Client
      # Base URL of the web API.
      BASE_URL = "https://api-web.nhle.com/v1"

      # Base URL of the stats REST API (English).
      STATS_URL = "https://api.nhle.com/stats/rest/en"

      # The source recorded on errors and used for the cache TTL.
      SOURCE = :nhl

      # @param http [#get, nil] what requests go through; +nil+ means a {Cache::Raw} around an
      #   {HTTP::Client} for +:nhl+
      # @param configuration [Configuration, nil] settings to read; +nil+ means
      #   {SportsIngest.configuration} at request time
      def initialize(http: nil, configuration: nil)
        @http = http || Cache::Raw.new(client: HTTP::Client.new(source: SOURCE, configuration: configuration),
          configuration: configuration)
      end

      # Fetches a web API path and parses the JSON body.
      #
      # @param path [String] the path after +/v1/+, e.g. +"schedule/2026-11-23"+
      # @param params [Hash{#to_s => #to_s}] query parameters
      # @return [Hash, Array] the parsed JSON
      # @raise [NotFound] on 404
      # @raise [HTTPError] on any other failure, as {HTTP::Client#get} does
      # @raise [ParseError] if the body isn't JSON
      def get_json(path, params: {})
        parse(get(url_for(path), params: params))
      end

      # Fetches a stats REST API path and parses the JSON body.
      #
      # @param path [String] the path after +/stats/rest/en/+, e.g. +"skater/summary"+
      # @param params [Hash{#to_s => #to_s}] query parameters, such as +cayenneExp+, +start+, +limit+
      # @return [Hash, Array] the parsed JSON
      # @raise [NotFound] on 404
      # @raise [HTTPError] on any other failure, as {HTTP::Client#get} does
      # @raise [ParseError] if the body isn't JSON
      def stats_json(path, params: {})
        parse(get(url_for(path, base: STATS_URL), params: params))
      end

      # Fetches a URL. Use it over {#get_json} when you need the response's +fetched_at+ or +stale+.
      #
      # @param url [String] the full URL
      # @param params [Hash{#to_s => #to_s}] query parameters
      # @return [HTTP::Response] the response, possibly from the raw cache
      # @raise [NotFound] on 404
      # @raise [HTTPError] on any other failure, as {HTTP::Client#get} does
      def get(url, params: {})
        @http.get(url, params: params)
      end

      # Parses a response body as JSON.
      #
      # @param response [HTTP::Response] a response from {#get}
      # @return [Hash, Array] the parsed JSON
      # @raise [ParseError] if the body isn't JSON
      def parse(response)
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise ParseError.new("NHL sent a body that isn't JSON from #{response.url}: #{e.message[0, 100]}",
          source: SOURCE)
      end

      # @param path [String] the path after the base URL
      # @param base [String] {BASE_URL} or {STATS_URL}
      # @return [String] the full URL
      def url_for(path, base: BASE_URL)
        "#{base}/#{path.to_s.delete_prefix("/")}"
      end

      # @return [String]
      def inspect
        "#<#{self.class.name} #{BASE_URL}>"
      end
    end
  end
end
