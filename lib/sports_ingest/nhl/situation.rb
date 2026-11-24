# frozen_string_literal: true

module SportsIngest
  module NHL
    # Who is on the ice in a live game when it isn't plain five-on-five (ADR 0019): a power play,
    # a pulled goalie, or both. The NHL sends one only while that lasts, so a {GameScore} at even
    # strength has none.
    #
    # The skater counts and goalies come from the NHL's four-digit +situationCode+, which reads
    # away goalie, away skaters, home skaters, home goalie: +"1451"+ is a home power play, five
    # skaters against four with both goalies in.
    #
    # @!attribute [r] code
    #   @return [String] the NHL's +situationCode+, such as +"1451"+
    # @!attribute [r] home_skaters
    #   @return [Integer] home skaters on the ice, goalie not counted
    # @!attribute [r] away_skaters
    #   @return [Integer] away skaters on the ice, goalie not counted
    # @!attribute [r] home_goalie_in
    #   @return [Boolean] whether the home goalie is in net
    # @!attribute [r] away_goalie_in
    #   @return [Boolean] whether the away goalie is in net
    # @!attribute [r] seconds_remaining
    #   @return [Integer, nil] seconds left in the situation (the penalty), when the NHL gives one
    # @!attribute [r] home_descriptions
    #   @return [Array<String>] the NHL's labels for the home side, such as +["PP"]+ or +["EN"]+
    # @!attribute [r] away_descriptions
    #   @return [Array<String>] the NHL's labels for the away side
    #
    # @example
    #   score = SportsIngest::NHL.scores.find(&:power_play)
    #   score.power_play               # => :away
    #   score.situation.strength(:away) # => "5v4"
    #   score.situation.clock           # => "04:00"
    Situation = Model.define(:code, :home_skaters, :away_skaters, :home_goalie_in, :away_goalie_in,
      :seconds_remaining, :home_descriptions, :away_descriptions)

    # Reopened so methods resolve inside the class.
    class Situation
      # The sides of a game, as {#power_play} and {#empty_net} name them.
      SIDES = %i[home away].freeze

      # @param code [String] the NHL's four-digit +situationCode+
      # @param seconds_remaining [Integer, nil] seconds left in the situation, not negative
      # @param home_descriptions [Array<String>]
      # @param away_descriptions [Array<String>]
      # @param counts [Hash] +home_skaters+, +away_skaters+, +home_goalie_in+ and +away_goalie_in+,
      #   which must agree with +code+ when given (they're there so {.from_h} round-trips)
      # @raise [ArgumentError] if +code+ isn't four digits, a count disagrees with it, or another
      #   field is the wrong type
      def initialize(code:, seconds_remaining: nil, home_descriptions: [], away_descriptions: [], **counts)
        unless code.is_a?(String) && code.match?(/\A[01]\d\d[01]\z/)
          raise ArgumentError, "code must be a four-digit situationCode such as \"1451\", got #{code.inspect}"
        end
        if !seconds_remaining.nil? && !(seconds_remaining.is_a?(Integer) && !seconds_remaining.negative?)
          raise ArgumentError, "seconds_remaining must be a non-negative Integer or nil, got #{seconds_remaining.inspect}"
        end

        decoded = self.class.decode(code)
        counts.each do |name, value|
          raise ArgumentError, "unknown field #{name.inspect}" unless decoded.key?(name)
          raise ArgumentError, "#{name} is #{value.inspect} but code #{code} says #{decoded[name].inspect}" unless value == decoded[name]
        end

        super(
          code: code, seconds_remaining: seconds_remaining, **decoded,
          home_descriptions: coerce_descriptions(:home_descriptions, home_descriptions),
          away_descriptions: coerce_descriptions(:away_descriptions, away_descriptions)
        )
      end

      # The side on the power play: more skaters than the other side while both goalies are in.
      # A pulled goalie's extra attacker isn't a power play.
      #
      # @return [Symbol, nil] +:home+, +:away+, or +nil+ for none
      def power_play
        return nil unless home_goalie_in && away_goalie_in
        return nil if home_skaters == away_skaters

        (home_skaters > away_skaters) ? :home : :away
      end

      # @return [Array<Symbol>] the sides whose goalie is out of the net, +:home+ and/or +:away+
      def empty_net
        SIDES.reject { |side| public_send(:"#{side}_goalie_in") }
      end

      # Skaters on the ice from one side's point of view.
      #
      # @param side [Symbol] +:home+ or +:away+
      # @return [String] such as +"5v4"+, that side's skaters first
      # @raise [ArgumentError] if +side+ isn't +:home+ or +:away+
      def strength(side)
        raise ArgumentError, "side must be :home or :away, got #{side.inspect}" unless SIDES.include?(side)

        other = (side == :home) ? :away : :home
        "#{public_send(:"#{side}_skaters")}v#{public_send(:"#{other}_skaters")}"
      end

      # The time left in the situation as the NHL shows it.
      #
      # @return [String, nil] +MM:SS+, or +nil+ when the NHL gave none
      def clock
        return nil if seconds_remaining.nil?

        format("%02d:%02d", *seconds_remaining.divmod(60))
      end

      class << self
        # @api private
        # The skater counts and goalies a +situationCode+ stands for.
        #
        # @param code [String] four digits: away goalie, away skaters, home skaters, home goalie
        # @return [Hash{Symbol => Integer, Boolean}]
        def decode(code)
          away_goalie, away_skaters, home_skaters, home_goalie = code.chars.map(&:to_i)
          {home_skaters: home_skaters, away_skaters: away_skaters,
           home_goalie_in: home_goalie == 1, away_goalie_in: away_goalie == 1}
        end

        # @api private
        # Builds a situation from the NHL's +situation+ object (in +/score+ and gamecenter payloads).
        #
        # @param situation [Hash]
        # @return [Situation]
        # @raise [KeyError, ArgumentError, TypeError] if it isn't shaped as expected; callers turn
        #   these into {SourceChangedError}
        def parse(situation)
          new(
            code: situation.fetch("situationCode"),
            seconds_remaining: situation["secondsRemaining"],
            home_descriptions: situation.fetch("homeTeam").fetch("situationDescriptions", []),
            away_descriptions: situation.fetch("awayTeam").fetch("situationDescriptions", [])
          )
        end
      end

      private

      def coerce_descriptions(name, value)
        return value if value.is_a?(Array) && value.all?(String)

        raise ArgumentError, "#{name} must be an Array of Strings, got #{value.inspect}"
      end
    end
  end
end
