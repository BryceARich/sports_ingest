# frozen_string_literal: true

module SportsIngest
  # Raised when a configuration value (from a +configure+ block or an env var) is invalid.
  #
  # @example
  #   SportsIngest.configure { |c| c.default_ttl = "soon" } # raises ConfigurationError
  class ConfigurationError < Error
  end
end
