# frozen_string_literal: true

require "json"

module SportsIngest
  module NHL
    # Reads the NHL's public web API (+api-web.nhle.com/v1+). No auth.
    #
    # Requests go through {Cache::Raw} with the +:nhl+ TTL unless +http:+ is given. Endpoints and
    # quirks are in +docs/sources/nhl.md+.
    #
    # @example
    #   SportsIngest::NHL::Client.new.get_json("schedule/2026-11-23")["gameWeek"]
    class Client
      # Everything before the path.
      BASE_URL = "https://api-web.nhle.com/v1"

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

      # Fetches a path and parses the JSON body.
      #
      # @param path [String] the path after +/v1/+, e.g. +"schedule/2026-11-23"+
      # @return [Hash, Array] the parsed JSON
      # @raise [NotFound] on 404
      # @raise [HTTPError] on any other failure, as {HTTP::Client#get} does
      # @raise [ParseError] if the body isn't JSON
      def get_json(path)
        response = @http.get(url_for(path))
        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise ParseError.new("NHL sent a body that isn't JSON from #{response.url}: #{e.message[0, 100]}",
          source: SOURCE)
      end

      # @param path [String] the path after +/v1/+
      # @return [String] the full URL
      def url_for(path)
        "#{BASE_URL}/#{path.to_s.delete_prefix("/")}"
      end

      # @return [String]
      def inspect
        "#<#{self.class.name} #{BASE_URL}>"
      end
    end
  end
end
