# frozen_string_literal: true

module SportsIngest
  module NHL
    # How often to re-read a game, from where it stands (ADR 0025). It recommends a wait; it doesn't
    # sleep or fetch. Callers pass a {GameScore} from {NHL.scores} and wait the returned seconds.
    #
    # The waits are a guide, not a contract: fast while play is live, slow between periods, and no
    # more polling once the game is final.
    module PollInterval
      # Seconds to wait, by {GameScore#phase}. +nil+ means stop polling.
      SECONDS = {
        pre: 60,
        regulation: 10,
        overtime: 10,
        shootout: 10,
        intermission: 30,
        final: nil,
        unknown: 60
      }.freeze

      # @param score [GameScore] a game from {NHL.scores}
      # @return [Integer, nil] seconds to wait before the next read, or +nil+ once the game is final
      # @raise [ArgumentError] if +score+ isn't a {GameScore}
      # @example
      #   SportsIngest::NHL::PollInterval.for(score) # => 10
      def self.for(score)
        raise ArgumentError, "expected a GameScore, got #{score.class}" unless score.is_a?(GameScore)

        for_phase(score.phase)
      end

      # @param phase [Symbol] one of {GameScore#phase}'s values
      # @return [Integer, nil] seconds to wait, or +nil+ for +:final+
      # @raise [ArgumentError] if +phase+ isn't one of {GameScore#phase}'s values
      # @example
      #   SportsIngest::NHL::PollInterval.for_phase(:intermission) # => 30
      def self.for_phase(phase)
        raise ArgumentError, "unknown phase #{phase.inspect}" unless SECONDS.key?(phase)

        SECONDS.fetch(phase)
      end
    end
  end
end
