# frozen_string_literal: true

module SportsIngest
  # Wraps a secret value (an ESPN cookie, for example) so it can't leak by accident.
  #
  # +to_s+, +inspect+, +pretty_print+ and +to_json+ all print {REDACTED}, so a secret that ends up in a log
  # line, an exception message, a console session or a serialized hash shows as
  # <tt>[REDACTED]</tt>. Call {#reveal} at the one place that needs the real value, such as
  # building a +Cookie+ header.
  #
  # @example
  #   secret = SportsIngest::Secret.new("AEB2...")
  #   "s2=#{secret}" # => "s2=[REDACTED]"
  #   secret.reveal  # => "AEB2..."
  class Secret
    # What a secret prints as everywhere except {#reveal}.
    REDACTED = "[REDACTED]"

    # @param value [String] the secret value
    # @raise [ConfigurationError] if +value+ is not a non-empty String
    # @example
    #   SportsIngest::Secret.new(ENV.fetch("SPORTS_INGEST_ESPN_S2"))
    def initialize(value)
      unless value.is_a?(String) && !value.empty?
        raise ConfigurationError, "a secret must be a non-empty String, got #{value.class}"
      end

      @value = value.dup.freeze
      freeze
    end

    # Returns the real value. Call it only where the value is sent to its source.
    #
    # @return [String] the unredacted value
    # @example
    #   headers["Cookie"] = "espn_s2=#{config.espn_s2.reveal}"
    def reveal
      @value
    end

    # @return [String] always {REDACTED}
    # @example
    #   SportsIngest::Secret.new("abc").to_s # => "[REDACTED]"
    def to_s
      REDACTED
    end

    # @return [String] a redacted description that never includes the value
    # @example
    #   SportsIngest::Secret.new("abc").inspect # => "#<SportsIngest::Secret [REDACTED]>"
    def inspect
      "#<#{self.class.name} #{REDACTED}>"
    end

    # Keeps +pp+ (and IRB's echo) from printing the value.
    #
    # @param pp [PP] the pretty printer
    # @return [void]
    # @example
    #   pp SportsIngest::Secret.new("abc") # prints #<SportsIngest::Secret [REDACTED]>
    def pretty_print(pp)
      pp.text(inspect)
    end

    # @param _args [Array] ignored; accepted for compatibility with +JSON.generate+
    # @return [String] {REDACTED} as a JSON string
    # @example
    #   JSON.generate(s2: SportsIngest::Secret.new("abc")) # => "{\"s2\":\"[REDACTED]\"}"
    def to_json(*_args)
      %("#{REDACTED}")
    end

    # Two secrets are equal when their values are equal.
    #
    # @param other [Object] the object to compare
    # @return [Boolean] whether +other+ is a {Secret} holding the same value
    # @example
    #   SportsIngest::Secret.new("a") == SportsIngest::Secret.new("a") # => true
    def ==(other)
      other.is_a?(Secret) && other.reveal == @value
    end
    alias_method :eql?, :==

    # @return [Integer] a hash consistent with {#==}
    # @example
    #   SportsIngest::Secret.new("a").hash == SportsIngest::Secret.new("a").hash # => true
    def hash
      [self.class, @value].hash
    end
  end
end
