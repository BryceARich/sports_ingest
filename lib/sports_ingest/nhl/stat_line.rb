# frozen_string_literal: true

module SportsIngest
  module NHL
    # A player's totals over a span: one season with one team, or a career (part of
    # {PlayerDetails}).
    #
    # Skaters and goalies share the model. A stat the NHL doesn't send for that line is +nil+:
    # goalie fields on a skater, faceoffs on a defenceman's junior season, everything but games,
    # goals, assists and points for most non-NHL leagues.
    #
    # @!attribute [r] season
    #   @return [Integer, nil] the season's start year (ADR 0006); +nil+ for career totals
    # @!attribute [r] game_type
    #   @return [Symbol] +:regular+ or +:playoffs+ (one of {Game::GAME_TYPES}' values), or +:other+
    # @!attribute [r] league
    #   @return [String, nil] such as +"NHL"+ or +"OHL"+; +nil+ for career totals, which are NHL only
    # @!attribute [r] team_name
    #   @return [String, nil] such as +"Edmonton Oilers"+; +nil+ for career totals
    # @!attribute [r] games_played
    #   @return [Integer, nil]
    # @!attribute [r] goals
    #   @return [Integer, nil]
    # @!attribute [r] assists
    #   @return [Integer, nil]
    # @!attribute [r] points
    #   @return [Integer, nil]
    # @!attribute [r] plus_minus
    #   @return [Integer, nil]
    # @!attribute [r] pim
    #   @return [Integer, nil] penalty minutes
    # @!attribute [r] shots
    #   @return [Integer, nil]
    # @!attribute [r] shooting_pct
    #   @return [Float, nil] goals over shots, such as +0.1517+
    # @!attribute [r] power_play_goals
    #   @return [Integer, nil]
    # @!attribute [r] power_play_points
    #   @return [Integer, nil]
    # @!attribute [r] shorthanded_goals
    #   @return [Integer, nil]
    # @!attribute [r] shorthanded_points
    #   @return [Integer, nil]
    # @!attribute [r] game_winning_goals
    #   @return [Integer, nil]
    # @!attribute [r] ot_goals
    #   @return [Integer, nil]
    # @!attribute [r] faceoff_pct
    #   @return [Float, nil] faceoffs won over taken
    # @!attribute [r] avg_toi_seconds
    #   @return [Integer, nil] a skater's average time on ice per game, in seconds
    # @!attribute [r] games_started
    #   @return [Integer, nil] goalies only
    # @!attribute [r] wins
    #   @return [Integer, nil] goalies only
    # @!attribute [r] losses
    #   @return [Integer, nil] goalies only, regulation losses
    # @!attribute [r] ot_losses
    #   @return [Integer, nil] goalies only, overtime and shootout losses
    # @!attribute [r] shutouts
    #   @return [Integer, nil] goalies only
    # @!attribute [r] goals_against
    #   @return [Integer, nil] goalies only
    # @!attribute [r] shots_against
    #   @return [Integer, nil] goalies only
    # @!attribute [r] goals_against_avg
    #   @return [Float, nil] goalies only
    # @!attribute [r] save_pct
    #   @return [Float, nil] goalies only, such as +0.905+
    # @!attribute [r] toi_seconds
    #   @return [Integer, nil] a goalie's total time on ice, in seconds
    #
    # @example
    #   details = SportsIngest::NHL::Players.new.fetch(8478402)
    #   details.career_regular_season.points   # => 1278
    #   details.nhl_seasons.last.avg_toi_seconds # => 1422
    StatLine = Model.define(:season, :game_type, :league, :team_name, :games_played, :goals, :assists,
      :points, :plus_minus, :pim, :shots, :shooting_pct, :power_play_goals, :power_play_points,
      :shorthanded_goals, :shorthanded_points, :game_winning_goals, :ot_goals, :faceoff_pct,
      :avg_toi_seconds, :games_started, :wins, :losses, :ot_losses, :shutouts, :goals_against,
      :shots_against, :goals_against_avg, :save_pct, :toi_seconds)

    # Reopened so constants and methods resolve inside the class.
    class StatLine
      # The stat fields, all optional.
      STATS = (members - %i[season game_type league team_name]).freeze

      # @param season [Integer, nil] the season's start year
      # @param game_type [Symbol, String] +:regular+, +:playoffs+ or another {Game::GAME_TYPES} value
      # @param league [String, nil]
      # @param team_name [String, nil]
      # @param stats [Hash{Symbol => Integer, Float, nil}] any of {STATS}; the rest are +nil+
      # @raise [ArgumentError] if +season+ isn't an Integer or +nil+, +game_type+ is unknown, or a
      #   stat isn't one of {STATS}
      def initialize(game_type:, season: nil, league: nil, team_name: nil, **stats)
        self.class.check_integer(:season, season, allow_nil: true)

        unknown = stats.keys - STATS
        raise ArgumentError, "unknown stats #{unknown.inspect}" unless unknown.empty?

        super(season: season, game_type: Game.coerce_coded(:game_type, game_type), league: league,
              team_name: team_name, **STATS.to_h { [it, nil] }.merge(stats))
      end

      # @return [Boolean] whether this line is from the NHL (career totals count as NHL)
      def nhl?
        league.nil? || league == "NHL"
      end
    end
  end
end
