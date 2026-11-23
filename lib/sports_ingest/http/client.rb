# frozen_string_literal: true

require "net/http"
require "openssl"
require "stringio"
require "uri"
require "zlib"

module SportsIngest
  module HTTP
    # Makes GET requests for one source. The only class in the gem that talks to the network.
    #
    # - **Timeouts:** +open_timeout+ and +read_timeout+, in seconds.
    # - **Retries:** 429, 5xx, timeouts and connection errors are retried up to +max_retries+ times,
    #   waiting {Backoff#delay} between tries (which honours +Retry-After+).
    # - **Rate limits:** every request, retries and redirects included, waits its turn on the
    #   {RateLimiter} for its host.
    # - **Headers:** +User-Agent+ comes from {SportsIngest::Configuration#user_agent} at request time;
    #   +Accept-Encoding: gzip+ is sent and gzip bodies are decoded.
    # - **Redirects:** followed up to {MAX_REDIRECTS} times. Caller headers (cookies, say) are
    #   dropped when a redirect leaves the original host.
    # - **Errors** (ADR 0012): 401/403 raise {AuthError}, 404 {NotFound}, anything else that isn't
    #   2xx after retries {HTTPError}. A broken gzip body raises {ParseError}.
    #
    # @example
    #   client = SportsIngest::HTTP::Client.new(source: :nhl)
    #   response = client.get("https://api.nhle.com/stats/rest/en/skater/summary",
    #     params: {cayenneExp: "seasonId=20242025"})
    #   JSON.parse(response.body)
    class Client
      # Seconds to wait for a connection, by default.
      DEFAULT_OPEN_TIMEOUT = 5

      # Seconds to wait for each read, by default.
      DEFAULT_READ_TIMEOUT = 15

      # Retries after the first try, by default.
      DEFAULT_MAX_RETRIES = 3

      # Redirects followed before giving up.
      MAX_REDIRECTS = 5

      # Statuses that are retried, besides every 5xx.
      RETRY_STATUSES = [408, 429].freeze

      # Statuses that are followed as redirects when they carry a +Location+.
      REDIRECT_STATUSES = [301, 302, 303, 307, 308].freeze

      # Library errors that mean the request didn't get a response. They are retried, then
      # raised as {HTTPError} with the original as +cause+.
      NETWORK_ERRORS = [
        Timeout::Error, # includes Net::OpenTimeout and Net::ReadTimeout
        Net::WriteTimeout,
        IOError, # includes EOFError
        SocketError,
        SystemCallError, # Errno::ECONNREFUSED, ECONNRESET, EHOSTUNREACH, ...
        OpenSSL::SSL::SSLError,
        Net::HTTPBadResponse
      ].freeze

      # @return [Symbol, nil] the source this client fetches for; set on every error it raises
      attr_reader :source

      # @return [Integer] retries after the first try
      attr_reader :max_retries

      # @param source [Symbol, nil] the source, e.g. +:nhl+, recorded on errors
      # @param open_timeout [Numeric] seconds to wait for a connection
      # @param read_timeout [Numeric] seconds to wait for each read
      # @param max_retries [Integer] retries after the first try; 0 turns retrying off
      # @param backoff [Backoff] the delays between retries
      # @param rate_limiter [RateLimiter] the per-host limiter; shared {RateLimiter.default} unless given
      # @param sleeper [#call] sleeps between retries; swap it in tests
      # @param configuration [Configuration, nil] settings to read the user agent from; +nil+ means
      #   {SportsIngest.configuration} at request time
      # @raise [ConfigurationError] if +max_retries+ is not a non-negative Integer
      def initialize(source: nil, open_timeout: DEFAULT_OPEN_TIMEOUT, read_timeout: DEFAULT_READ_TIMEOUT,
        max_retries: DEFAULT_MAX_RETRIES, backoff: Backoff.new, rate_limiter: RateLimiter.default,
        sleeper: ->(seconds) { sleep(seconds) }, configuration: nil)
        unless max_retries.is_a?(Integer) && max_retries >= 0
          raise ConfigurationError, "max_retries must be a non-negative Integer, got #{max_retries.inspect}"
        end

        @source = source
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @max_retries = max_retries
        @backoff = backoff
        @rate_limiter = rate_limiter
        @sleeper = sleeper
        @configuration = configuration
      end

      # Fetches +url+ with GET.
      #
      # @param url [String, URI::HTTP] an +http+ or +https+ URL
      # @param params [Hash{#to_s => #to_s}] query parameters, added to any already in +url+
      # @param headers [Hash{String => String, Secret}] extra request headers; {Secret} values are
      #   revealed only on the wire
      # @return [Response] the 2xx response, body decoded
      # @raise [AuthError] on 401 or 403
      # @raise [NotFound] on 404
      # @raise [HTTPError] on any other non-2xx status after retries, a timeout or connection error
      #   after retries, too many redirects, or a URL that isn't http(s)
      # @raise [ParseError] if a gzip body can't be decoded
      # @example
      #   client.get("https://lm-api-reads.fantasy.espn.com/apis/v3/games/fhl/seasons/2025",
      #     headers: {"Cookie" => cookie_secret})
      def get(url, params: {}, headers: {})
        uri = build_uri(url, params)
        origin_host = uri.host
        redirects = 0

        loop do
          sent = (uri.host == origin_host) ? headers : {}
          response = fetch_with_retries(uri, sent)
          location = response.header("location")
          return response if (200..299).cover?(response.status)
          raise error_for(response) unless REDIRECT_STATUSES.include?(response.status) && location

          redirects += 1
          raise HTTPError.new("too many redirects (#{MAX_REDIRECTS})", url: uri.to_s, source: source) if redirects > MAX_REDIRECTS

          uri = build_uri(uri.merge(location), {})
        end
      end

      # @return [String] a summary that never includes header values
      def inspect
        "#<#{self.class.name} source=#{source.inspect} max_retries=#{max_retries}>"
      end

      private

      def configuration
        @configuration || SportsIngest.configuration
      end

      def build_uri(url, params)
        uri = URI(url.to_s)
        unless uri.is_a?(URI::HTTP) && uri.host
          raise HTTPError.new("not an http(s) URL: #{url}", url: url.to_s, source: source)
        end

        unless params.empty?
          query = URI.decode_www_form(uri.query.to_s) + params.map { |key, value| [key.to_s, value.to_s] }
          uri.query = URI.encode_www_form(query)
        end
        uri
      rescue URI::InvalidURIError => e
        raise HTTPError.new("invalid URL: #{e.message}", url: url.to_s, source: source)
      end

      def fetch_with_retries(uri, headers)
        attempt = 0
        loop do
          response = begin
            perform(uri, headers)
          rescue *NETWORK_ERRORS => e
            if attempt >= max_retries
              raise HTTPError.new("#{e.class}: #{e.message} for #{uri}", url: uri.to_s, source: source)
            end
          end
          return response if response && (attempt >= max_retries || !retry_status?(response.status))

          @sleeper.call(@backoff.delay(attempt, retry_after: response&.header("retry-after")))
          attempt += 1
        end
      end

      def retry_status?(status)
        status >= 500 || RETRY_STATUSES.include?(status)
      end

      def perform(uri, headers)
        @rate_limiter.wait(uri.host)
        raw = connection(uri).start { |http| http.request(build_request(uri, headers)) }
        response_headers = raw.to_hash.transform_values { |values| values.join(", ") }
        Response.new(status: raw.code.to_i, headers: response_headers, body: decode(raw, response_headers, uri),
          url: uri.to_s)
      end

      def connection(uri)
        Net::HTTP.new(uri.host, uri.port).tap do |http|
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = @open_timeout
          http.read_timeout = @read_timeout
          http.write_timeout = @read_timeout
        end
      end

      def build_request(uri, headers)
        Net::HTTP::Get.new(uri).tap do |request|
          request["User-Agent"] = configuration.user_agent
          # Setting Accept-Encoding ourselves turns off Net::HTTP's own decoding; #decode does it.
          request["Accept-Encoding"] = "gzip"
          headers.each { |name, value| request[name.to_s] = value.is_a?(Secret) ? value.reveal : value.to_s }
        end
      end

      def decode(raw, headers, uri)
        body = raw.body.to_s.dup
        if headers["content-encoding"].to_s.downcase.include?("gzip") && !body.empty?
          body = Zlib::GzipReader.new(StringIO.new(body)).read
        end
        body.force_encoding(body_encoding(headers["content-type"].to_s))
      rescue Zlib::Error => e
        raise ParseError.new("can't decode gzip body from #{uri}: #{e.message}", source: source)
      end

      def body_encoding(content_type)
        charset = content_type[/charset="?([\w-]+)/i, 1]
        begin
          return Encoding.find(charset) if charset
        rescue ArgumentError
          # An unknown charset; fall back to guessing from the media type.
        end
        content_type.match?(%r{\Atext/|json|xml|csv}i) ? Encoding::UTF_8 : Encoding::BINARY
      end

      def error_for(response)
        message = "HTTP #{response.status} for #{response.url}"
        case response.status
        when 401, 403 then AuthError.new(message, source: source)
        when 404 then NotFound.new(message, source: source)
        else HTTPError.new(status: response.status, url: response.url, source: source)
        end
      end
    end
  end
end
