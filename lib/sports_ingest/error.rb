# frozen_string_literal: true

module SportsIngest
  # Base class for every error the gem raises. Rescue this to catch them all.
  #
  # Subclasses (ADR 0012): {HTTPError}, {AuthError}, {NotFound}, {ParseError} and
  # {SourceChangedError}. The underlying library error, if any, is kept as +cause+.
  #
  # @example
  #   begin
  #     SportsIngest.configure { |c| c.default_ttl = -1 }
  #   rescue SportsIngest::Error => e
  #     warn e.message
  #   end
  class Error < StandardError
    # @return [Symbol, nil] the source that failed, such as +:nhl+ or +:espn+
    attr_reader :source

    # @param message [String, nil] what went wrong
    # @param source [Symbol, nil] the source that failed
    def initialize(message = nil, source: nil)
      @source = source
      super(message)
    end
  end
end
