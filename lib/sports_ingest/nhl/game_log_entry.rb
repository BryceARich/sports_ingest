# frozen_string_literal: true

require "date"

module SportsIngest
  module NHL
    # One player's line in one game, from +/player/{id}/game-log/{season}/{gameType}+.
    #
    # Skaters and goalies share the model; stats the NHL doesn't send for that player are +nil+
    # (goalie fields on a skater, shots and shifts on a goalie).
    #
    # @!attribute [r] player_id
    #   @return [String] the NHL player ID
    # @!attribute [r] game_id
    #   @return [String] the NHL game ID, as on {Game#id}
    # @!attribute [r] season
    #   @return [Integer] the season's start year (ADR 0006)
    # @!attribute [r] game_type
    #   @return [Symbol] +:regular+ or +:playoffs+
    # @!attribute [r] date
    #   @return [Date] the game date, local to the venue
    # @!attribute [r] team
    #   @return [String] the player's team tri-code, such as +"EDM"+
    # @!attribute [r] opponent
    #   @return [String] the opponent's tri-code
    # @!attribute [r] home
    #   @return [Boolean] whether the player's team was at home
    # @!attribute [r] toi_seconds
    #   @return [Integer, nil] time on ice, in seconds
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
    # @!attribute [r] shifts
    #   @return [Integer, nil]
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
    # @!attribute [r] games_started
    #   @return [Integer, nil] goalies only: 1 for a start, 0 in relief
    # @!attribute [r] decision
    #   @return [String, nil] goalies only: +"W"+, +"L"+ or +"O"+ (overtime or shootout loss);
    #     +nil+ without a decision
    # @!attribute [r] shots_against
    #   @return [Integer, nil] goalies only
    # @!attribute [r] goals_against
    #   @return [Integer, nil] goalies only
    # @!attribute [r] save_pct
    #   @return [Float, nil] goalies only
    # @!attribute [r] shutouts
    #   @return [Integer, nil] goalies only
    #
    # @example
    #   log = SportsIngest::NHL::Players.new.game_log(8478402, season: 2025)
    #   log.sum(&:points)  # => 138
    #   log.first.opponent # => "CGY"
    GameLogEntry = Model.define(:player_id, :game_id, :season, :game_type, :date, :team, :opponent, :home,
      :toi_seconds, :goals, :assists, :points, :plus_minus, :pim, :shots, :shifts, :power_play_goals,
      :power_play_points, :shorthanded_goals, :shorthanded_points, :game_winning_goals, :ot_goals,
      :games_started, :decision, :shots_against, :goals_against, :save_pct, :shutouts)

    # Reopened so constants and methods resolve inside the class.
    class GameLogEntry
      # The stat fields, all optional.
      STATS = (members - %i[player_id game_id season game_type date team opponent home]).freeze

      # @param player_id [String, Integer]
      # @param game_id [String, Integer]
      # @param season [Integer] the season's start year
      # @param game_type [Symbol, String] +:regular+, +:playoffs+ or another {Game::GAME_TYPES} value
      # @param date [Date, String] a Date or +YYYY-MM-DD+
      # @param team [String]
      # @param opponent [String]
      # @param home [Boolean]
      # @param stats [Hash{Symbol => Integer, Float, String, nil}] any of {STATS}; the rest are +nil+
      # @raise [ArgumentError] if an ID is blank, +season+ isn't an Integer, +date+ isn't a date,
      #   +home+ isn't a Boolean, +game_type+ is unknown, or a stat isn't one of {STATS}
      def initialize(player_id:, game_id:, season:, game_type:, date:, team:, opponent:, home:, **stats)
        raise ArgumentError, "season must be an Integer, got #{season.inspect}" unless season.is_a?(Integer)
        raise ArgumentError, "home must be true or false, got #{home.inspect}" unless [true, false].include?(home)

        unknown = stats.keys - STATS
        raise ArgumentError, "unknown stats #{unknown.inspect}" unless unknown.empty?

        super(player_id: Identity::PlayerRef.coerce_id(player_id), game_id: Identity::PlayerRef.coerce_id(game_id),
              season: season, game_type: Game.coerce_coded(:game_type, game_type), date: Game.coerce_date(date),
              team: Team.coerce_text(:team, team), opponent: Team.coerce_text(:opponent, opponent), home: home,
              **STATS.to_h { [it, nil] }.merge(stats))
      end

      # @return [Boolean] whether the player's team was on the road
      def road?
        !home
      end
    end
  end
end
