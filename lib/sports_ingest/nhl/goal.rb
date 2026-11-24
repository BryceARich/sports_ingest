# frozen_string_literal: true

module SportsIngest
  module NHL
    # One goal from a game's play-by-play (ADR 0020): who scored, who assisted, when, at what
    # strength, and the score after it.
    #
    # Shootout attempts aren't goals here; {GoalEvents} leaves them out. The {#strength} is from
    # the scoring side's point of view, read from the goal's own +situationCode+ (see {Situation}).
    #
    # @!attribute [r] event_id
    #   @return [Integer] the NHL's +eventId+, unique within a game; {GoalEvents.new_since} keys on it
    # @!attribute [r] game_id
    #   @return [Integer] the NHL game ID
    # @!attribute [r] period
    #   @return [Integer] the period the goal was scored in; 4 is the first overtime
    # @!attribute [r] time_in_period
    #   @return [String] elapsed time in the period, such as +"04:59"+
    # @!attribute [r] time_remaining
    #   @return [String] time left in the period, such as +"15:01"+
    # @!attribute [r] side
    #   @return [Symbol] +:home+ or +:away+, the side that scored
    # @!attribute [r] team_id
    #   @return [Integer] the scoring team's NHL ID
    # @!attribute [r] scorer_id
    #   @return [Integer] the scorer's NHL player ID
    # @!attribute [r] assist_ids
    #   @return [Array<Integer>] up to two assisters' NHL player IDs, primary first; empty if unassisted
    # @!attribute [r] strength
    #   @return [String] +"EV"+, +"PP"+ (scoring side has more skaters), +"SH"+ (fewer) or +"EN"+
    #     (the other side's goalie was out)
    # @!attribute [r] situation
    #   @return [Situation] the skaters and goalies on the ice when the goal was scored
    # @!attribute [r] shot_type
    #   @return [String, nil] the NHL's shot type, such as +"wrist"+, when given
    # @!attribute [r] home_score
    #   @return [Integer] the home team's score after this goal
    # @!attribute [r] away_score
    #   @return [Integer] the away team's score after this goal
    #
    # @example
    #   goal = SportsIngest::NHL.goals(2026020378).first
    #   "#{goal.time_in_period} P#{goal.period} #{goal.strength} #{goal.scorer_id}" # => "04:59 P1 EV 8478414"
    Goal = Model.define(:event_id, :game_id, :period, :time_in_period, :time_remaining, :side, :team_id,
      :scorer_id, :assist_ids, :strength, :situation, :shot_type, :home_score, :away_score)

    # Reopened so methods resolve inside the class.
    class Goal
      # The strengths a goal can have, as {#strength} names them.
      STRENGTHS = %w[EV PP SH EN].freeze

      # @param event_id [Integer] the NHL's +eventId+
      # @param game_id [Integer] the NHL game ID
      # @param period [Integer] a positive period number
      # @param time_in_period [String] +MM:SS+
      # @param time_remaining [String] +MM:SS+
      # @param side [Symbol, String] +:home+ or +:away+
      # @param team_id [Integer]
      # @param scorer_id [Integer]
      # @param assist_ids [Array<Integer>] at most two
      # @param strength [String] one of {STRENGTHS}
      # @param situation [Situation, Hash] the situation at the goal
      # @param shot_type [String, nil]
      # @param home_score [Integer] not negative
      # @param away_score [Integer] not negative
      # @raise [ArgumentError] if a field is the wrong type or out of range
      def initialize(event_id:, game_id:, period:, time_in_period:, time_remaining:, side:, team_id:,
        scorer_id:, strength:, situation:, home_score:, away_score:, assist_ids: [], shot_type: nil)
        check_integer(:event_id, event_id, min: 0)
        check_integer(:game_id, game_id, min: 0)
        check_integer(:period, period, min: 1)
        check_integer(:team_id, team_id, min: 0)
        check_integer(:scorer_id, scorer_id, min: 0)
        check_integer(:home_score, home_score, min: 0)
        check_integer(:away_score, away_score, min: 0)
        check_clock(:time_in_period, time_in_period)
        check_clock(:time_remaining, time_remaining)
        raise ArgumentError, "side must be :home or :away, got #{side.inspect}" unless %i[home away].include?(side.to_sym)
        raise ArgumentError, "strength must be one of #{STRENGTHS.join(", ")}, got #{strength.inspect}" unless STRENGTHS.include?(strength)
        unless assist_ids.is_a?(Array) && assist_ids.size <= 2 && assist_ids.all? { |id| id.is_a?(Integer) }
          raise ArgumentError, "assist_ids must be up to two Integers, got #{assist_ids.inspect}"
        end

        super(
          event_id: event_id, game_id: game_id, period: period, time_in_period: time_in_period,
          time_remaining: time_remaining, side: side.to_sym, team_id: team_id, scorer_id: scorer_id,
          assist_ids: assist_ids, strength: strength, situation: Situation.coerce(situation),
          shot_type: shot_type, home_score: home_score, away_score: away_score
        )
      end

      private

      def check_integer(name, value, min:)
        return if value.is_a?(Integer) && value >= min

        raise ArgumentError, "#{name} must be an Integer of at least #{min}, got #{value.inspect}"
      end

      def check_clock(name, value)
        return if value.is_a?(String) && value.match?(/\A\d{1,2}:\d{2}\z/)

        raise ArgumentError, "#{name} must be MM:SS, got #{value.inspect}"
      end
    end
  end
end
