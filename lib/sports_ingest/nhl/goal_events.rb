# frozen_string_literal: true

module SportsIngest
  module NHL
    # A game's goals, from +/gamecenter/{id}/play-by-play+ (ADR 0020), and the diff a poller needs.
    #
    # - **Goals only:** the payload's +goal+ plays, in the NHL's order. Shootout attempts are left
    #   out: they aren't goals for scoring or stats.
    # - **Polling:** the default client keeps entries fresh for {Scoreboard::TTL} seconds, so a loop
    #   that calls {#fetch} every few seconds sees new plays without waiting out the usual raw-cache
    #   TTL. Pass +client:+ to choose another.
    # - **Diffs:** {.new_since} returns goals in the current snapshot whose +eventId+ the previous one
    #   didn't have. Plays are appended, so this is the goal scored since the last poll.
    #
    # A payload that isn't shaped as expected raises {SourceChangedError}.
    #
    # @example Poll a live game and print each new goal
    #   goals = SportsIngest::NHL::GoalEvents.new
    #   seen = goals.fetch(2026020378)
    #   loop do
    #     sleep 30
    #     now = goals.fetch(2026020378)
    #     SportsIngest::NHL::GoalEvents.new_since(seen, now).each { |g| puts g.scorer_id }
    #     seen = now
    #   end
    class GoalEvents
      # @param client [Client, nil] what the NHL is read through; +nil+ means a new {Client} that keeps
      #   entries fresh for {Scoreboard::TTL} seconds
      def initialize(client: nil)
        @client = client || Client.new(ttl: Scoreboard::TTL)
      end

      # One game's goals so far.
      #
      # @param game_id [Integer, String] the NHL game ID, all digits
      # @return [Array<Goal>] in the NHL's order; empty before the first goal
      # @raise [ArgumentError] if +game_id+ isn't all digits
      # @raise [NotFound] if the NHL has no such game
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      # @raise [HTTPError, ParseError] if the request fails
      def fetch(game_id)
        id = game_id.to_s
        raise ArgumentError, "game_id must be all digits, got #{game_id.inspect}" unless id.match?(/\A\d+\z/)

        self.class.parse(@client.get_json("gamecenter/#{id}/play-by-play"))
      end

      class << self
        # The goals in one play-by-play payload.
        #
        # @param payload [Hash] the parsed +/gamecenter/{id}/play-by-play+ JSON
        # @return [Array<Goal>] in the NHL's order
        # @raise [SourceChangedError] if the payload isn't shaped as expected
        def parse(payload)
          plays = payload.fetch("plays")
          raise TypeError, "plays is a #{plays.class}, not an Array" unless plays.is_a?(Array)

          context = {
            game_id: payload.fetch("id"),
            home_id: payload.fetch("homeTeam").fetch("id"),
            away_id: payload.fetch("awayTeam").fetch("id")
          }
          plays.filter_map { |play| goal_from(play, context) if play.fetch("typeDescKey") == "goal" }
        rescue ArgumentError, KeyError, TypeError, NoMethodError => e
          id = payload["id"] if payload.is_a?(Hash)
          raise SourceChangedError.new("NHL play-by-play for game #{id.inspect} isn't shaped as expected: #{e.message}",
            source: Client::SOURCE)
        end

        # The goals in +current+ that +previous+ didn't have, matched on +eventId+.
        #
        # @param previous [Array<Goal>] the goals from the last poll (or empty, for the first)
        # @param current [Array<Goal>] the goals from this poll
        # @return [Array<Goal>] the new ones, in +current+'s order
        # @raise [ArgumentError] if either isn't an Array of {Goal}s
        def new_since(previous, current)
          [previous, current].each do |list|
            raise ArgumentError, "expected an Array of Goals, got #{list.class}" unless list.is_a?(Array) && list.all?(Goal)
          end

          seen = previous.map(&:event_id).to_set
          current.reject { |goal| seen.include?(goal.event_id) }
        end

        private

        def goal_from(play, context)
          descriptor = play.fetch("periodDescriptor")
          return nil if descriptor.fetch("periodType") == "SO"

          details = play.fetch("details")
          side = side_for(details.fetch("eventOwnerTeamId"), context)
          situation = Situation.new(code: play.fetch("situationCode"))
          Goal.new(
            event_id: play.fetch("eventId"), game_id: context[:game_id], period: descriptor.fetch("number"),
            time_in_period: play.fetch("timeInPeriod"), time_remaining: play.fetch("timeRemaining"),
            side: side, team_id: details.fetch("eventOwnerTeamId"), scorer_id: details.fetch("scoringPlayerId"),
            assist_ids: %w[assist1PlayerId assist2PlayerId].filter_map { |key| details[key] },
            strength: strength_for(situation, side), situation: situation, shot_type: details["shotType"],
            home_score: details.fetch("homeScore"), away_score: details.fetch("awayScore")
          )
        end

        def side_for(team_id, context)
          case team_id
          when context[:home_id] then :home
          when context[:away_id] then :away
          else raise ArgumentError, "goal team #{team_id.inspect} is neither side"
          end
        end

        # A goal against an empty net is "EN" whatever the skater count. Otherwise the scoring
        # side's skaters against the other side's say "PP", "SH" or "EV".
        def strength_for(situation, side)
          other = (side == :home) ? :away : :home
          return "EN" if situation.empty_net.include?(other)

          scoring = situation.public_send(:"#{side}_skaters")
          against = situation.public_send(:"#{other}_skaters")
          if scoring > against then "PP"
          elsif scoring < against then "SH"
          else "EV"
          end
        end
      end
    end
  end
end
