# frozen_string_literal: true

module SportsIngest
  module NHL
    # One game on the scoreboard (ADRs 0018 and 0019): the {Game}, with its scores and state, plus
    # where a game in progress stands: period, clock, shots on goal and any power play.
    #
    # The period, clock and shot fields are +nil+ before the game starts. After it ends, +period+
    # is the last one played and the clock shows what was left in it (zero, unless overtime ended
    # early). {#phase} sums it all up as one symbol.
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
    # @!attribute [r] home_shots
    #   @return [Integer, nil] the home team's shots on goal
    # @!attribute [r] away_shots
    #   @return [Integer, nil] the away team's shots on goal
    # @!attribute [r] situation
    #   @return [Situation, nil] the power play or pulled goalie under way; +nil+ at even strength
    #
    # @example
    #   score = SportsIngest::NHL.scores.find(&:live?)
    #   "#{score.away_team.tri_code} #{score.away_team.score}, #{score.home_team.tri_code} " \
    #     "#{score.home_team.score} (P#{score.period}, #{score.clock})" # => "CBJ 0, NJD 2 (P1, 08:16)"
    GameScore = Model.define(:game, :period, :period_type, :seconds_remaining, :clock_running, :in_intermission,
      :codes, :home_shots, :away_shots, :situation, schema_version: 2)

    # Reopened so methods resolve inside the class.
    class GameScore
      # @param game [Game, Hash]
      # @param period [Integer, nil] a positive period number
      # @param period_type [Symbol, String, nil] one of {Game::PERIOD_TYPES}' values or +:unknown+
      # @param seconds_remaining [Integer, nil] seconds left in the period, not negative
      # @param clock_running [Boolean, nil]
      # @param in_intermission [Boolean, nil]
      # @param codes [Hash{Symbol, String => String}] the NHL's raw period type, as +:period_type+
      # @param home_shots [Integer, nil] home shots on goal, not negative
      # @param away_shots [Integer, nil] away shots on goal, not negative
      # @param situation [Situation, Hash, nil]
      # @raise [ArgumentError] if a field is the wrong type or out of range
      def initialize(game:, period: nil, period_type: nil, seconds_remaining: nil, clock_running: nil,
        in_intermission: nil, codes: {}, home_shots: nil, away_shots: nil, situation: nil)
        self.class.check_integer(:period, period, min: 1, allow_nil: true)
        self.class.check_integer(:seconds_remaining, seconds_remaining, min: 0, allow_nil: true)
        self.class.check_integer(:home_shots, home_shots, min: 0, allow_nil: true)
        self.class.check_integer(:away_shots, away_shots, min: 0, allow_nil: true)
        self.class.check_boolean(:clock_running, clock_running, allow_nil: true)
        self.class.check_boolean(:in_intermission, in_intermission, allow_nil: true)

        super(
          game: Game.coerce(game), period: period,
          period_type: period_type && Game.coerce_coded(:ended_in, period_type),
          seconds_remaining: seconds_remaining, clock_running: clock_running, in_intermission: in_intermission,
          codes: self.class.coerce_codes(codes, keys: [:period_type]) do |_, code|
            raise ArgumentError, "codes[:period_type] must be a String" unless code.is_a?(String)

            code
          end,
          home_shots: home_shots, away_shots: away_shots,
          situation: situation && Situation.coerce(situation)
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

      # Where the game stands, as one symbol:
      #
      # - +:pre+: not started (scheduled or in pregame, postponed games included; see {Game#schedule_state})
      # - +:regulation+, +:overtime+, +:shootout+: in progress, in that kind of period
      # - +:intermission+: in progress, between periods
      # - +:final+: over; {Game#ended_in} says whether in regulation, overtime or a shootout
      # - +:unknown+: a game state or period type the gem doesn't know
      #
      # @return [Symbol]
      def phase
        case state
        when :scheduled, :pregame then :pre
        when :final then :final
        when :live
          return :intermission if in_intermission

          LIVE_PHASES.fetch(period_type, :unknown)
        else :unknown
        end
      end

      # Phases of a game in progress, by period type.
      LIVE_PHASES = {regulation: :regulation, overtime: :overtime, shootout: :shootout}.freeze

      # @return [Symbol, nil] the side on a power play, +:home+ or +:away+; +nil+ for none
      def power_play
        situation&.power_play
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
            codes: code ? {period_type: code} : {},
            home_shots: game.fetch("homeTeam")["sog"],
            away_shots: game.fetch("awayTeam")["sog"],
            situation: game["situation"] && Situation.parse(game["situation"])
          )
          Game.warn_unknown(:ended_in, code, built.id) if code
          built
        rescue ArgumentError, KeyError, TypeError, NoMethodError => e
          id = game["id"] if game.is_a?(Hash)
          raise SourceChangedError.new("NHL score for game #{id.inspect} isn't shaped as expected: #{e.message}",
            source: Client::SOURCE)
        end
      end
    end
  end
end
