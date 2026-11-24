# frozen_string_literal: true

module SportsIngest
  module NHL
    # One player's NHL totals for one season and game type, from the stats REST API's
    # +skater/summary+ or +goalie/summary+ table (ADR 0024).
    #
    # A player traded mid-season has one row for the season, with every team in {#teams}.
    #
    # @!attribute [r] player_id
    #   @return [String] the NHL player ID, such as +"8478402"+
    # @!attribute [r] full_name
    #   @return [String] such as +"Connor McDavid"+
    # @!attribute [r] position
    #   @return [String] +"C"+, +"L"+, +"R"+, +"D"+ or +"G"+
    # @!attribute [r] teams
    #   @return [Array<String>] tri-codes in the order the NHL lists them, such as +["TOR", "EDM"]+
    # @!attribute [r] stats
    #   @return [StatLine] the totals; +league+ is +"NHL"+ and +team_name+ is +nil+
    #
    # @example
    #   row = SportsIngest::NHL.skater_stats(last: 3).max_by { it.stats.points }
    #   [row.full_name, row.season, row.stats.points]
    SeasonTotal = Model.define(:player_id, :full_name, :position, :teams, :stats)

    # Reopened so methods resolve inside the class.
    class SeasonTotal
      # @param player_id [String, Integer]
      # @param full_name [String]
      # @param position [String]
      # @param teams [Array<String>]
      # @param stats [StatLine, Hash]
      # @raise [ArgumentError] if +player_id+ isn't all digits, +teams+ isn't an Array, or +stats+
      #   has no season
      def initialize(player_id:, full_name:, position:, teams:, stats:)
        player_id = player_id.to_s
        raise ArgumentError, "player_id must be all digits, got #{player_id.inspect}" unless /\A\d+\z/.match?(player_id)
        raise ArgumentError, "teams must be an Array, got #{teams.class}" unless teams.is_a?(Array)

        stats = StatLine.coerce(stats)
        raise ArgumentError, "stats must name a season" if stats.season.nil?

        super
      end

      # @return [Integer] the season's start year (ADR 0006)
      def season
        stats.season
      end

      # @return [Symbol] +:regular+ or +:playoffs+
      def game_type
        stats.game_type
      end

      # @return [Boolean] whether the row is a goalie's
      def goalie?
        position == "G"
      end
    end
  end
end
