# frozen_string_literal: true

module SportsIngest
  module NHL
    # One game on the scoreboard (ADR 0018): the {Game}, with its scores and state, plus where a
    # game in progress stands: period and clock.
    #
    # The period and clock fields are +nil+ before the game starts. After it ends, +period+ is the
    # last one played and the clock reads zero.
    #
    # @!attribute [r] game
    #   @return [Game] the game, with both sides' scores once it has started
    # @!attribute [r] period
    #   @return [Integer, nil] the current (or last) period number, overtime and shootout included:
    #     +4+ is the first overtime in a regular-season game, +5+ a shootout
    # @!attribute [r] period_type
    #   @return [Symbol, nil] one of {Game::PERIOD_TYPES}' values, or +:unknown+
    # @!attribute [r] seconds_remaining
    #   @return [Integer, nil] seconds left in the period
    # @!attribute [r] clock_running
    #   @return [Boolean, nil] whether the clock is running
    # @!attribute [r] in_intermission
    #   @return [Boolean, nil] whether the game is between periods
    # @!attribute [r] codes
    #   @return [Hash{Symbol => String}] the NHL's raw +periodDescriptor.periodType+ as
    #     +:period_type+, when the payload had one
    #
    # @example
    #   score = SportsIngest::NHL.scores.find(&:live?)
    #   "#{score.away_team.tri_code} #{score.away_team.score}, #{score.home_team.tri_code} " \
    #     "#{score.home_team.score} (P#{score.period}, #{score.clock})" # => "CBJ 0, NJD 2 (P1, 08:16)"
    GameScore = Model.define(:game, :period, :period_type, :seconds_remaining, :clock_running, :in_intermission,
      :codes)

    # Reopened so methods resolve inside the class.
    class GameScore
      # @param game [Game, Hash]
      # @param period [Integer, nil] a positive period number
      # @param period_type [Symbol, String, nil] one of {Game::PERIOD_TYPES}' values or +:unknown+
      # @param seconds_remaining [Integer, nil] seconds left in the period, not negative
      # @param clock_running [Boolean, nil]
      # @param in_intermission [Boolean, nil]
      # @param codes [Hash{Symbol, String => String}] the NHL's raw period type, as +:period_type+
      # @raise [ArgumentError] if a field is the wrong type or out of range
      def initialize(game:, period: nil, period_type: nil, seconds_remaining: nil, clock_running: nil,
        in_intermission: nil, codes: {})
        check_count(:period, period, min: 1)
        check_count(:seconds_remaining, seconds_remaining, min: 0)
        {clock_running: clock_running, in_intermission: in_intermission}.each do |name, value|
          raise ArgumentError, "#{name} must be true, false or nil, got #{value.inspect}" unless [true, false, nil].include?(value)
        end

        super(
          game: Game.coerce(game), period: period,
          period_type: period_type && Game.coerce_coded(:ended_in, period_type),
          seconds_remaining: seconds_remaining, clock_running: clock_running, in_intermission: in_intermission,
          codes: coerce_codes(codes)
        )
      end

      # @return [String] the NHL game ID
      def id
        game.id
      end

      # @return [GameTeam]
      def home_team
        game.home_team
      end

      # @return [GameTeam]
      def away_team
        game.away_team
      end

      # @return [Symbol] the game's state, as {Game#state}
      def state
        game.state
      end

      # @return [Boolean] whether the game is in progress
      def live?
        game.live?
      end

      # @return [Boolean] whether the game is over
      def final?
        game.final?
      end

      # The time left in the period as the NHL shows it.
      #
      # @return [String, nil] +MM:SS+, or +nil+ before the game starts
      def clock
        return nil if seconds_remaining.nil?

        format("%02d:%02d", *seconds_remaining.divmod(60))
      end

      class << self
        # @api private
        # Builds a score from one game of the NHL's +/score/{date}+ payload.
        #
        # @param game [Hash] the NHL's game object
        # @return [GameScore]
        # @raise [SourceChangedError] if a field is missing or the wrong type
        def parse(game)
          descriptor = game["periodDescriptor"]
          clock = game["clock"]
          code = descriptor&.fetch("periodType")
          built = new(
            game: Game.parse(game, date: game.fetch("gameDate")),
            period: descriptor&.fetch("number"),
            period_type: code && Game.from_code(:ended_in, code),
            seconds_remaining: clock&.fetch("secondsRemaining"),
            clock_running: clock&.fetch("running"),
            in_intermission: clock&.fetch("inIntermission"),
            codes: code ? {period_type: code} : {}
          )
          Game.warn_unknown(:ended_in, code, built.id) if code
          built
        rescue ArgumentError, KeyError, TypeError, NoMethodError => e
          id = game["id"] if game.is_a?(Hash)
          raise SourceChangedError.new("NHL score for game #{id.inspect} isn't shaped as expected: #{e.message}",
            source: Client::SOURCE)
        end
      end

      private

      def check_count(name, value, min:)
        return if value.nil? || (value.is_a?(Integer) && value >= min)

        raise ArgumentError, "#{name} must be an Integer of at least #{min} or nil, got #{value.inspect}"
      end

      def coerce_codes(codes)
        raise ArgumentError, "codes must be a Hash, got #{codes.class}" unless codes.is_a?(Hash)

        codes.to_h do |field, code|
          raise ArgumentError, "codes has no field #{field.inspect}" unless field.to_sym == :period_type
          raise ArgumentError, "codes[:period_type] must be a String" unless code.is_a?(String)

          [:period_type, code]
        end
      end
    end
  end
end
