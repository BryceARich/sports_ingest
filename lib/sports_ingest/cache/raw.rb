# frozen_string_literal: true

require "digest"
require "json"
require "time"

module SportsIngest
  module Cache
    # The raw cache tier: wraps an {HTTP::Client} and answers {#get} from a store when it can
    # (ADR 0009 in +docs/adr/0009-raw-cache-stores-and-stale-on-error.md+).
    #
    # - **Key:** the source, the URL, the params and the request headers, hashed with SHA-256.
    #   Header values ({Secret}s included) only ever enter the digest, never the store.
    # - **Fresh:** an entry younger than the source's TTL ({Configuration#ttl_for}) is returned
    #   without a request. A TTL of 0 always refetches.
    # - **Stale on error:** if the request fails with no response, or with 408, 429 or 5xx after
    #   the client's retries, the newest stored entry is returned with +stale: true+, however old.
    #   {AuthError}, {NotFound} and {ParseError} are always raised.
    # - **Stored:** status, response headers (minus +Set-Cookie+), body, URL and +fetched_at+.
    #
    # @example
    #   client = SportsIngest::Cache::Raw.new(client: SportsIngest::HTTP::Client.new(source: :nhl))
    #   response = client.get("https://api-web.nhle.com/v1/standings/now")
    #   response.fetched_at # when it came from the network
    #   response.stale      # true if served from the cache because the network failed
    class Raw
      # Bumped when the stored entry layout changes; entries with another version read as misses.
      SCHEMA_VERSION = 1

      # Response headers never written to the store.
      UNSTORED_HEADERS = %w[set-cookie].freeze

      # Statuses that count as the network failing, so a stale entry is served.
      STALE_STATUSES = [408, 429].freeze

      # The store for a mode, shared by every {Raw} that doesn't get one of its own.
      #
      # @param mode [Symbol] +:disk+, +:memory+ or +:off+
      # @param configuration [Configuration] settings to read +cache_dir+ from, for +:disk+
      # @return [DiskStore, MemoryStore, NullStore] a {DiskStore} under +<cache_dir>/raw+, one
      #   process-wide {MemoryStore}, or a {NullStore}
      # @raise [ConfigurationError] for an unknown mode
      def self.store_for(mode, configuration = SportsIngest.configuration)
        case mode
        when :disk then DiskStore.new(configuration.cache_dir.join("raw"))
        when :memory then @memory_store ||= MemoryStore.new
        when :off then NullStore.new
        else raise ConfigurationError, "unknown raw cache mode #{mode.inspect}; use one of #{MODES.join(", ")}"
        end
      end

      # @return [HTTP::Client, #get] the client requests go through
      attr_reader :client

      # @param client [HTTP::Client, #get, #source] the client to wrap
      # @param store [DiskStore, MemoryStore, NullStore, nil] where entries live; +nil+ means
      #   {.store_for}({Configuration#raw_cache}) at request time
      # @param ttl [Integer, nil] seconds an entry stays fresh; +nil+ means
      #   {Configuration#ttl_for}(client.source) at request time
      # @param configuration [Configuration, nil] settings to read; +nil+ means
      #   {SportsIngest.configuration} at request time
      # @param clock [#call] returns the current Time; swap it in tests
      # @raise [ConfigurationError] if +ttl+ is given and isn't a non-negative Integer
      def initialize(client:, store: nil, ttl: nil, configuration: nil, clock: -> { Time.now })
        if !ttl.nil? && !(ttl.is_a?(Integer) && ttl >= 0)
          raise ConfigurationError, "ttl must be a non-negative Integer, got #{ttl.inspect}"
        end

        @client = client
        @store = store
        @ttl = ttl
        @configuration = configuration
        @clock = clock
      end

      # @return [Symbol, nil] the wrapped client's source
      def source
        client.respond_to?(:source) ? client.source : nil
      end

      # Fetches +url+ through the cache. Takes the same arguments as {HTTP::Client#get}.
      #
      # @param url [String, URI::HTTP] an +http+ or +https+ URL
      # @param params [Hash{#to_s => #to_s}] query parameters
      # @param headers [Hash{String => String, Secret}] extra request headers
      # @return [HTTP::Response] a fresh cached response, a new one, or (when the network fails) a
      #   stale cached one with +stale: true+
      # @raise [AuthError, NotFound, ParseError] as {HTTP::Client#get} does
      # @raise [HTTPError] as {HTTP::Client#get} does, when nothing is cached to fall back on
      # @raise [Error] if the disk store can't write
      def get(url, params: {}, headers: {})
        key = key_for(url, params, headers)
        cached = load(key)
        return cached if cached && fresh?(cached)

        begin
          response = client.get(url, params: params, headers: headers)
        rescue HTTPError => e
          raise unless cached && network_failure?(e)

          return cached.with(stale: true)
        end

        store.write(key, dump(response))
        response
      end

      # The store key for a request.
      #
      # @param url [String, URI::HTTP] the URL
      # @param params [Hash] query parameters
      # @param headers [Hash{String => String, Secret}] request headers
      # @return [String] +"<source>/<2 hex>/<sha256 hex>"+
      def key_for(url, params = {}, headers = {})
        request = [
          source.to_s,
          url.to_s,
          params.map { |name, value| [name.to_s, value.to_s] },
          headers.map { |name, value| [name.to_s.downcase, value.is_a?(Secret) ? value.reveal : value.to_s] }.sort
        ]
        digest = Digest::SHA256.hexdigest(JSON.generate(request))
        "#{source || "default"}/#{digest[0, 2]}/#{digest}"
      end

      # @return [String] a summary that never includes cached contents or header values
      def inspect
        "#<#{self.class.name} source=#{source.inspect} store=#{store.inspect}>"
      end

      private

      def configuration
        @configuration || SportsIngest.configuration
      end

      def store
        @store || self.class.store_for(configuration.raw_cache, configuration)
      end

      def ttl
        @ttl || configuration.ttl_for(source || :default)
      end

      def fresh?(response)
        ttl.positive? && @clock.call - response.fetched_at < ttl
      end

      def network_failure?(error)
        error.status.nil? || error.status >= 500 || STALE_STATUSES.include?(error.status)
      end

      def dump(response)
        body = response.body
        text = body.encoding == Encoding::UTF_8 && body.valid_encoding?
        {
          "schema_version" => SCHEMA_VERSION,
          "status" => response.status,
          "headers" => response.headers.except(*UNSTORED_HEADERS),
          "url" => response.url,
          "fetched_at" => response.fetched_at.utc.iso8601(6),
          "encoding" => body.encoding.name,
          (text ? "body" : "body_base64") => (text ? body : [body].pack("m0"))
        }
      end

      def load(key)
        entry = store.read(key)
        return nil unless entry.is_a?(Hash) && entry["schema_version"] == SCHEMA_VERSION

        body = entry.key?("body") ? entry["body"].dup : entry["body_base64"].unpack1("m0")
        HTTP::Response.new(status: entry["status"], headers: entry["headers"].dup,
          body: body.force_encoding(entry["encoding"]), url: entry["url"],
          fetched_at: Time.iso8601(entry["fetched_at"]))
      rescue ArgumentError, TypeError, NoMethodError
        nil # a damaged entry reads as a miss
      end
    end
  end
end
