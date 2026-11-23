# frozen_string_literal: true

require "time"

module SportsIngest
  module HTTP
    # How long {Client} waits before each retry: exponential backoff with jitter, or the server's
    # +Retry-After+ when it sends one. Every delay is capped at +max+.
    #
    # @example
    #   backoff = SportsIngest::HTTP::Backoff.new(base: 1, jitter: 0)
    #   (0..3).map { |attempt| backoff.delay(attempt) } # => [1.0, 2.0, 4.0, 8.0]
    class Backoff
      # @return [Float] seconds before the first retry, before jitter
      attr_reader :base

      # @return [Float] the longest delay, in seconds
      attr_reader :max

      # @return [Float] the largest fraction added at random to each delay, e.g. 0.25 for up to +25%
      attr_reader :jitter

      # @param base [Numeric] seconds before the first retry, before jitter
      # @param max [Numeric] the longest delay, in seconds
      # @param jitter [Numeric] up to this fraction of each delay is added at random, so clients
      #   that failed together don't retry together
      # @param random [Random] the random source, for repeatable tests
      # @raise [ConfigurationError] if a number is negative
      def initialize(base: 0.5, max: 30, jitter: 0.25, random: Random.new)
        @base, @max, @jitter = [base, max, jitter].map do |value|
          next value.to_f if value.is_a?(Numeric) && value >= 0

          raise ConfigurationError, "backoff settings must be non-negative numbers, got #{value.inspect}"
        end
        @random = random
      end

      # The delay before retry number +attempt+.
      #
      # @param attempt [Integer] retries already made: 0 before the first retry
      # @param retry_after [String, nil] the response's +Retry-After+ header: seconds or an HTTP date
      # @return [Float] seconds to wait, never more than {#max}
      # @example
      #   backoff.delay(2)                    # => about 2.0 with base 0.5, plus jitter
      #   backoff.delay(0, retry_after: "7")  # => 7.0
      def delay(attempt, retry_after: nil)
        server = parse_retry_after(retry_after)
        return [server, max].min if server

        exponential = base * (2**attempt)
        [exponential * (1 + (jitter * @random.rand)), max].min
      end

      private

      def parse_retry_after(value)
        return nil if value.nil? || value.strip.empty?

        seconds = Integer(value.strip, exception: false) || (Time.httpdate(value.strip) - Time.now)
        [seconds.to_f, 0.0].max
      rescue ArgumentError
        nil
      end
    end
  end
end
