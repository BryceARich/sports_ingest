# frozen_string_literal: true

require "date"
require "time"

module SportsIngest
  module NHL
    # One NHL game as the schedule lists it (ADR 0017): who, when, where, and where it stands.
    #
    # +date+ is the NHL's game date, local to the venue, so a 7 p.m. Pacific start is on the date
    # fans see even though +start_time+ (UTC) falls on the next day.
    #
    # @!attribute [r] id
    #   @return [String] the NHL game ID, such as +"2026020378"+
    # @!attribute [r] season
    #   @return [Integer] the year the season starts (ADR 0006): +2026+ for 2026-27
    # @!attribute [r] game_type
    #   @return [Symbol] one of {GAME_TYPES}' values
    # @!attribute [r] date
    #   @return [Date] the game date, local to the venue
    # @!attribute [r] start_time
    #   @return [Time] the scheduled start, in UTC
    # @!attribute [r] state
    #   @return [Symbol] one of {STATES}' values
    # @!attribute [r] schedule_state
    #   @return [Symbol] one of {SCHEDULE_STATES}' values
    # @!attribute [r] ended_in
    #   @return [Symbol, nil] how a finished game ended, one of {PERIOD_TYPES}' values; +nil+ until then
    # @!attribute [r] venue
    #   @return [String, nil] the arena
    # @!attribute [r] neutral_site
    #   @return [Boolean] whether neither team is at home (global series and the like)
    # @!attribute [r] home_team
    #   @return [GameTeam]
    # @!attribute [r] away_team
    #   @return [GameTeam]
    #
    # @example
    #   game = SportsIngest::NHL.schedule(date: "2026-11-23").first
    #   game.away_team.tri_code # => "CBJ"
    #   game.home_team.team.name # => "New Jersey Devils"
    #   game.final?              # => false
    Game = Model.define(:id, :season, :game_type, :date, :start_time, :state, :schedule_state, :ended_in,
      :venue, :neutral_site, :home_team, :away_team)

    # Reopened so constants and methods resolve inside the class.
    class Game
      # The NHL's +gameType+ numbers.
      GAME_TYPES = {1 => :preseason, 2 => :regular, 3 => :playoffs, 4 => :all_star}.freeze

      # The NHL's +gameState+ codes. +OFF+ is a final game whose stats are official.
      STATES = {"FUT" => :scheduled, "PRE" => :pregame, "LIVE" => :live, "CRIT" => :live,
                "FINAL" => :final, "OFF" => :final}.freeze

      # The NHL's +gameScheduleState+ codes.
      SCHEDULE_STATES = {"OK" => :ok, "PPD" => :postponed, "SUSP" => :suspended, "CNCL" => :cancelled,
                         "TBD" => :to_be_decided}.freeze

      # The NHL's +periodType+ codes, used for +ended_in+.
      PERIOD_TYPES = {"REG" => :regulation, "OT" => :overtime, "SO" => :shootout}.freeze

      # @param id [String, Integer] the NHL game ID
      # @param season [Integer] the season's start year
      # @param game_type [Symbol, String] one of {GAME_TYPES}' values
      # @param date [Date, String] the game date, or +YYYY-MM-DD+
      # @param start_time [Time, String] the start, or a time string such as ISO 8601
      # @param state [Symbol, String] one of {STATES}' values
      # @param schedule_state [Symbol, String] one of {SCHEDULE_STATES}' values
      # @param ended_in [Symbol, String, nil] one of {PERIOD_TYPES}' values
      # @param venue [String, nil] the arena
      # @param neutral_site [Boolean]
      # @param home_team [GameTeam, Hash]
      # @param away_team [GameTeam, Hash]
      # @raise [ArgumentError] if a field is missing, the wrong type, or not one of its allowed values
      def initialize(id:, season:, game_type:, date:, start_time:, state:, schedule_state:, home_team:,
        away_team:, ended_in: nil, venue: nil, neutral_site: false)
        raise ArgumentError, "season must be an Integer, got #{season.inspect}" unless season.is_a?(Integer)
        raise ArgumentError, "neutral_site must be true or false" unless [true, false].include?(neutral_site)

        super(
          id: Identity::PlayerRef.coerce_id(id), season: season,
          game_type: self.class.coerce_symbol(:game_type, game_type, GAME_TYPES.values),
          date: self.class.coerce_date(date), start_time: self.class.coerce_time(start_time),
          state: self.class.coerce_symbol(:state, state, STATES.values),
          schedule_state: self.class.coerce_symbol(:schedule_state, schedule_state, SCHEDULE_STATES.values),
          ended_in: ended_in && self.class.coerce_symbol(:ended_in, ended_in, PERIOD_TYPES.values),
          venue: venue, neutral_site: neutral_site,
          home_team: GameTeam.coerce(home_team), away_team: GameTeam.coerce(away_team)
        )
      end

      # @return [Boolean] whether the game is over
      def final?
        state == :final
      end

      # @return [Boolean] whether the game is in progress
      def live?
        state == :live
      end

      # Whether a team plays in this game.
      #
      # @param team [Team, String, Integer] a {Team}, or an NHL team ID
      # @return [Boolean]
      def involves?(team)
        id = team.is_a?(Team) ? team.id : team.to_s
        [home_team.id, away_team.id].include?(id)
      end

      class << self
        # @api private
        # @param field [Symbol]
        # @param value [Symbol, String]
        # @param allowed [Array<Symbol>]
        # @return [Symbol]
        # @raise [ArgumentError] if it isn't one of +allowed+
        def coerce_symbol(field, value, allowed)
          symbol = value.to_s.to_sym if value.is_a?(String) || value.is_a?(Symbol)
          return symbol if allowed.include?(symbol)

          raise ArgumentError, "#{field} must be one of #{allowed.join(", ")}, got #{value.inspect}"
        end

        # @api private
        # @param value [Date, String]
        # @return [Date]
        # @raise [ArgumentError] if it isn't a Date or a +YYYY-MM-DD+ String
        def coerce_date(value)
          return value if value.instance_of?(Date)
          raise ArgumentError, "date must be a Date or YYYY-MM-DD, got #{value.inspect}" unless value.is_a?(String)

          Date.iso8601(value)
        rescue Date::Error
          raise ArgumentError, "date must be a Date or YYYY-MM-DD, got #{value.inspect}"
        end

        # @api private
        # @param value [Time, String]
        # @return [Time] in UTC
        # @raise [ArgumentError] if it isn't a Time or a parseable String
        def coerce_time(value)
          return value.getutc if value.is_a?(Time)
          raise ArgumentError, "start_time must be a Time or String, got #{value.inspect}" unless value.is_a?(String)

          Time.parse(value).getutc
        end
      end
    end
  end
end
