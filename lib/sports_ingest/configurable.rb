# frozen_string_literal: true

module SportsIngest
  # The module-level configuration API, extended into {SportsIngest}:
  # {#configure}, {#configuration} and {#reset_configuration!}.
  module Configurable
    # The current configuration, built from defaults and the environment on first use.
    #
    # @return [Configuration]
    # @raise [ConfigurationError] if a +SPORTS_INGEST_*+ env var holds an invalid value
    # @example
    #   SportsIngest.configuration.cache_dir # => #<Pathname:/Users/me/.cache/sports_ingest>
    def configuration
      @configuration ||= Configuration.new
    end

    # Changes settings in a block. Values set here override env vars.
    #
    # @yieldparam config [Configuration] the current configuration
    # @return [Configuration] the updated configuration
    # @raise [ConfigurationError] if a value set in the block is invalid
    # @example
    #   SportsIngest.configure do |config|
    #     config.user_agent = "my-dashboard/1.0"
    #     config.ttls = {espn: 300}
    #   end
    def configure
      yield configuration if block_given?
      configuration
    end

    # Throws away the current configuration so the next {#configuration} call rebuilds it from
    # defaults and the environment. Mostly useful in tests.
    #
    # @return [void]
    # @example
    #   SportsIngest.reset_configuration!
    def reset_configuration!
      @configuration = nil
    end
  end
end
