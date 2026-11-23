# frozen_string_literal: true

module SportsIngest
  # Settings for the whole gem: cache directory, HTTP user agent, per-source cache TTLs and the
  # ESPN private-league cookies.
  #
  # Values come from three layers, later ones winning: built-in defaults, then +SPORTS_INGEST_*+
  # environment variables (read when the configuration is created), then a
  # {SportsIngest.configure} block.
  #
  # | Setting | Env var | Default |
  # |---|---|---|
  # | {#cache_dir} | +SPORTS_INGEST_CACHE_DIR+ | +$XDG_CACHE_HOME/sports_ingest+, else +~/.cache/sports_ingest+ |
  # | {#user_agent} | +SPORTS_INGEST_USER_AGENT+ | +sports_ingest/<version> (+<homepage>)+ |
  # | {#raw_cache} | +SPORTS_INGEST_RAW_CACHE+ (+disk+, +memory+ or +off+) | +:disk+ |
  # | {#default_ttl} | +SPORTS_INGEST_TTL+ | 3600 seconds |
  # | {#ttl_for}(source) | +SPORTS_INGEST_TTL_<SOURCE>+, e.g. +SPORTS_INGEST_TTL_NHL+ | {DEFAULT_TTLS} |
  # | {#espn_s2} | +SPORTS_INGEST_ESPN_S2+ | none |
  # | {#espn_swid} | +SPORTS_INGEST_ESPN_SWID+ | none |
  #
  # The ESPN cookies are held as {Secret}s, so +inspect+, +to_s+, {#to_h} and anything that logs
  # them print <tt>[REDACTED]</tt>.
  #
  # @example Configure in code
  #   SportsIngest.configure do |config|
  #     config.cache_dir = "/var/cache/sports_ingest"
  #     config.ttls = {nhl: 600}
  #     config.espn_s2 = ENV.fetch("MY_ESPN_S2")
  #   end
  #
  # @example Configure from the environment
  #   # SPORTS_INGEST_CACHE_DIR=/tmp/si SPORTS_INGEST_TTL_ESPN=300 bin/console
  #   SportsIngest.configuration.ttl_for(:espn) # => 300
  class Configuration
    # Prefix shared by every environment variable the gem reads.
    ENV_PREFIX = "SPORTS_INGEST_"

    # TTL used for a source with no TTL of its own, in seconds.
    DEFAULT_TTL = 3600

    # Built-in raw-cache TTLs per source, in seconds.
    DEFAULT_TTLS = {
      nhl: 3600,
      espn: 900,
      nflverse: 86_400
    }.freeze

    # @return [Pathname] directory the raw and processed caches live under. Defaults to a
    #   per-user cache directory outside any repository.
    attr_reader :cache_dir

    # @return [Symbol] where the raw HTTP cache keeps responses: +:disk+ (under {#cache_dir}),
    #   +:memory+ (for the life of the process) or +:off+
    attr_reader :raw_cache

    # @return [String] +User-Agent+ header sent with every HTTP request
    attr_reader :user_agent

    # @return [Integer] TTL in seconds for sources with no entry in {#ttls}
    attr_reader :default_ttl

    # @return [Secret, nil] the ESPN +espn_s2+ cookie, for private leagues
    attr_reader :espn_s2

    # @return [Secret, nil] the ESPN +SWID+ cookie, for private leagues
    attr_reader :espn_swid

    # Builds a configuration from the defaults and the environment.
    #
    # @param env [#[], #each] where to read +SPORTS_INGEST_*+ variables from; pass a Hash in tests
    # @raise [ConfigurationError] if an env var holds an invalid value (e.g. a non-numeric TTL)
    # @example
    #   SportsIngest::Configuration.new(env: {"SPORTS_INGEST_TTL_NHL" => "60"}).ttl_for(:nhl) # => 60
    def initialize(env: ENV)
      @ttls = DEFAULT_TTLS.dup
      self.cache_dir = default_cache_dir(env)
      self.user_agent = "sports_ingest/#{VERSION} (+https://github.com/BryceARich/sports_ingest)"
      self.default_ttl = DEFAULT_TTL
      self.raw_cache = :disk
      @espn_s2 = nil
      @espn_swid = nil
      load_env(env)
    end

    # @param path [String, Pathname] cache directory; +~+ is expanded
    # @return [void]
    # @raise [ConfigurationError] if +path+ is blank
    # @example
    #   config.cache_dir = "~/sports_cache"
    def cache_dir=(path)
      raise ConfigurationError, "cache_dir must not be blank" if path.nil? || path.to_s.strip.empty?

      @cache_dir = Pathname.new(File.expand_path(path.to_s))
    end

    # @param value [String] the +User-Agent+ header value
    # @return [void]
    # @raise [ConfigurationError] if +value+ is blank
    # @example
    #   config.user_agent = "my-dashboard/1.0 (me@example.com)"
    def user_agent=(value)
      raise ConfigurationError, "user_agent must not be blank" if value.nil? || value.to_s.strip.empty?

      @user_agent = value.to_s.dup.freeze
    end

    # @param mode [Symbol, String] +:disk+, +:memory+ or +:off+
    # @return [void]
    # @raise [ConfigurationError] for any other value
    # @example
    #   config.raw_cache = :memory # nothing written to disk, e.g. in a short-lived script
    def raw_cache=(mode)
      value = mode.to_s.strip.downcase.to_sym if mode.is_a?(Symbol) || mode.is_a?(String)
      unless Cache::MODES.include?(value)
        raise ConfigurationError, "raw_cache must be one of #{Cache::MODES.join(", ")}, got #{mode.inspect}"
      end

      @raw_cache = value
    end

    # @param seconds [Integer, String] TTL for sources with no TTL of their own
    # @return [void]
    # @raise [ConfigurationError] unless +seconds+ is a non-negative integer
    # @example
    #   config.default_ttl = 1800
    def default_ttl=(seconds)
      @default_ttl = coerce_ttl(seconds, "default_ttl")
    end

    # Per-source TTLs, including the built-in defaults.
    #
    # @return [Hash{Symbol => Integer}] a frozen copy; change TTLs with {#ttls=}
    # @example
    #   config.ttls # => {nhl: 3600, espn: 900, nflverse: 86400}
    def ttls
      @ttls.dup.freeze
    end

    # Merges per-source TTLs over the current ones. Sources not named keep their TTL.
    #
    # @param overrides [Hash{Symbol, String => Integer, String}] source name to seconds
    # @return [void]
    # @raise [ConfigurationError] if a value is not a non-negative integer
    # @example
    #   config.ttls = {nhl: 600, nflverse: 0} # 0 means always refetch
    def ttls=(overrides)
      raise ConfigurationError, "ttls must be a Hash, got #{overrides.class}" unless overrides.is_a?(Hash)

      overrides.each { |source, seconds| @ttls[source.to_sym] = coerce_ttl(seconds, "ttls[#{source}]") }
    end

    # The raw-cache TTL for one source.
    #
    # @param source [Symbol, String] the source name, e.g. +:nhl+
    # @return [Integer] seconds; {#default_ttl} if the source has no TTL of its own
    # @example
    #   config.ttl_for(:espn)    # => 900
    #   config.ttl_for(:unknown) # => 3600
    def ttl_for(source)
      @ttls.fetch(source.to_sym, default_ttl)
    end

    # @param value [String, Secret, nil] the +espn_s2+ cookie; +nil+ clears it
    # @return [void]
    # @raise [ConfigurationError] if +value+ is an empty String or not a String
    # @example
    #   config.espn_s2 = "AEB..."
    def espn_s2=(value)
      @espn_s2 = coerce_secret(value)
    end

    # @param value [String, Secret, nil] the +SWID+ cookie, e.g. "{1A2B...}"; +nil+ clears it
    # @return [void]
    # @raise [ConfigurationError] if +value+ is an empty String or not a String
    # @example
    #   config.espn_swid = "{1A2B3C4D-...}"
    def espn_swid=(value)
      @espn_swid = coerce_secret(value)
    end

    # Whether both ESPN cookies are set, which private leagues need.
    #
    # @return [Boolean]
    # @example
    #   config.espn_credentials? # => false
    def espn_credentials?
      !espn_s2.nil? && !espn_swid.nil?
    end

    # Every setting as a Hash, with secrets redacted. Safe to log.
    #
    # @return [Hash{Symbol => Object}]
    # @example
    #   config.to_h[:espn_s2] # => "[REDACTED]" (or nil when unset)
    def to_h
      {
        cache_dir: cache_dir.to_s,
        user_agent: user_agent,
        raw_cache: raw_cache,
        default_ttl: default_ttl,
        ttls: ttls,
        espn_s2: espn_s2&.to_s,
        espn_swid: espn_swid&.to_s
      }
    end

    # @return [String] the settings with secrets redacted
    # @example
    #   config.inspect # => "#<SportsIngest::Configuration cache_dir=... espn_s2=[REDACTED] ...>"
    def inspect
      fields = to_h.map { |key, value| "#{key}=#{value.nil? ? "nil" : value}" }
      "#<#{self.class.name} #{fields.join(" ")}>"
    end
    alias_method :to_s, :inspect

    # Keeps +pp+ (and IRB's echo) from bypassing {#inspect}.
    #
    # @param pp [PP] the pretty printer
    # @return [void]
    # @example
    #   pp SportsIngest.configuration
    def pretty_print(pp)
      pp.text(inspect)
    end

    private

    def default_cache_dir(env)
      xdg = env_value(env, "XDG_CACHE_HOME", prefixed: false)
      base = xdg || File.join(Dir.home, ".cache")
      File.join(base, "sports_ingest")
    end

    def load_env(env)
      read = ->(name) { env_value(env, name) }

      read.call("CACHE_DIR")&.then { |v| self.cache_dir = v }
      read.call("USER_AGENT")&.then { |v| self.user_agent = v }
      read.call("RAW_CACHE")&.then { |v| self.raw_cache = v }
      read.call("TTL")&.then { |v| self.default_ttl = v }
      read.call("ESPN_S2")&.then { |v| self.espn_s2 = v }
      read.call("ESPN_SWID")&.then { |v| self.espn_swid = v }

      env.each do |name, value|
        source = name[/\A#{ENV_PREFIX}TTL_(\w+)\z/o, 1]
        next if source.nil? || value.to_s.strip.empty?

        self.ttls = {source.downcase.to_sym => value}
      end
    end

    # Empty env vars count as unset.
    def env_value(env, name, prefixed: true)
      value = env[prefixed ? "#{ENV_PREFIX}#{name}" : name]
      (value.nil? || value.strip.empty?) ? nil : value
    end

    def coerce_ttl(seconds, name)
      ttl = Integer(seconds, exception: false) if seconds.is_a?(Integer) || seconds.is_a?(String)
      return ttl if ttl && ttl >= 0

      raise ConfigurationError, "#{name} must be a non-negative integer number of seconds, got #{seconds.inspect}"
    end

    def coerce_secret(value)
      case value
      when nil, Secret then value
      else Secret.new(value)
      end
    end
  end
end
