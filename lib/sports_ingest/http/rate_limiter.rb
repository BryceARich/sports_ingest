# frozen_string_literal: true

module SportsIngest
  module HTTP
    # Spaces out requests to the same host: at most one request per host every +interval+ seconds.
    #
    # Each call to {#wait} reserves the host's next free slot under a lock, then sleeps outside it,
    # so concurrent threads queue up instead of bursting. Every {Client} shares {.default} unless
    # given its own, so the limit holds across sources that call the same host.
    #
    # @example Give one host a slower limit
    #   SportsIngest::HTTP::RateLimiter.default.limit("api.nhle.com", 1.0)
    class RateLimiter
      # Seconds between requests to a host with no limit of its own.
      DEFAULT_INTERVAL = 0.5

      # The limiter clients use unless given another.
      #
      # @return [RateLimiter]
      # @example
      #   SportsIngest::HTTP::RateLimiter.default.interval_for("api-web.nhle.com") # => 0.5
      def self.default
        @default
      end

      # @param interval [Numeric] seconds between requests to hosts with no limit of their own
      # @param intervals [Hash{String => Numeric}] per-host intervals, by host name
      # @param clock [#call] returns the current monotonic time in seconds
      # @param sleeper [#call] sleeps for the seconds it's given
      # @raise [ConfigurationError] if an interval is negative or not a number
      def initialize(interval: DEFAULT_INTERVAL, intervals: {},
        clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }, sleeper: ->(seconds) { sleep(seconds) })
        @interval = check_interval(interval)
        @intervals = {}
        @next_slot = {}
        @clock = clock
        @sleeper = sleeper
        @mutex = Mutex.new
        intervals.each { |host, seconds| limit(host, seconds) }
      end

      # Sets one host's interval.
      #
      # @param host [String] the host name, e.g. "api-web.nhle.com"
      # @param seconds [Numeric] minimum seconds between requests to it; 0 turns limiting off
      # @return [void]
      # @raise [ConfigurationError] if +seconds+ is negative or not a number
      def limit(host, seconds)
        seconds = check_interval(seconds)
        @mutex.synchronize { @intervals[host.to_s.downcase] = seconds }
      end

      # @param host [String] the host name
      # @return [Numeric] the seconds between requests to +host+
      def interval_for(host)
        @mutex.synchronize { @intervals.fetch(host.to_s.downcase, @interval) }
      end

      # Blocks until a request to +host+ is allowed, and reserves that slot.
      #
      # @param host [String] the host about to be called
      # @return [Float] the seconds it waited
      def wait(host)
        delay = @mutex.synchronize do
          key = host.to_s.downcase
          now = @clock.call
          slot = [@next_slot.fetch(key, now), now].max
          @next_slot[key] = slot + @intervals.fetch(key, @interval)
          slot - now
        end
        @sleeper.call(delay) if delay.positive?
        delay.to_f
      end

      private

      def check_interval(seconds)
        return seconds if seconds.is_a?(Numeric) && seconds >= 0

        raise ConfigurationError, "a rate-limit interval must be a non-negative number of seconds, got #{seconds.inspect}"
      end

      @default = new
    end
  end
end
