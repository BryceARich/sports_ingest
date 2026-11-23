# frozen_string_literal: true

require "date"
require "time"

module SportsIngest
  module NHL
    # One NHL game as the schedule lists it (ADR 0017): who, when, where, and where it stands.
    #
    # Codes the gem doesn't know yet don't fail the game: an unknown +gameType+ becomes +:other+,
    # an unknown state, schedule state or period type +:unknown+, and +codes+ keeps the NHL's raw
    # values so callers can still tell them apart.
    #
    # +date+ is the NHL's game date, local to the venue, so a 7 p.m. Pacific start is on the date
    # fans see even though +start_time+ (UTC) falls on the next day.
    #
    # @!attribute [r] id
    #   @return [String] the NHL game ID, such as +"2026020378"+
    # @!attribute [r] season
    #   @return [Integer] the year the season starts (ADR 0006): +2026+ for 2026-27
    # @!attribute [r] game_type
    #   @return [Symbol] one of {GAME_TYPES}' values, or +:other+
    # @!attribute [r] date
    #   @return [Date] the game date, local to the venue
    # @!attribute [r] start_time
    #   @return [Time] the scheduled start, in UTC
    # @!attribute [r] state
    #   @return [Symbol] one of {STATES}' values, or +:unknown+
    # @!attribute [r] schedule_state
    #   @return [Symbol] one of {SCHEDULE_STATES}' values, or +:unknown+
    # @!attribute [r] ended_in
    #   @return [Symbol, nil] how a finished game ended, one of {PERIOD_TYPES}' values or +:unknown+;
    #     +nil+ until then
    # @!attribute [r] venue
    #   @return [String, nil] the arena
    # @!attribute [r] neutral_site
    #   @return [Boolean] whether neither team is at home (global series and the like)
    # @!attribute [r] home_team
    #   @return [GameTeam]
    # @!attribute [r] away_team
    #   @return [GameTeam]
    # @!attribute [r] codes
    #   @return [Hash{Symbol => String, Integer}] the NHL's raw codes behind +game_type+ (+gameType+),
    #     +state+ (+gameState+), +schedule_state+ (+gameScheduleState+) and +ended_in+
    #     (+lastPeriodType+), for the ones the payload had
    #
    # @example
    #   game = SportsIngest::NHL.schedule(date: "2026-11-23").first
    #   game.away_team.tri_code # => "CBJ"
    #   game.home_team.team.name # => "New Jersey Devils"
    #   game.final?              # => false
    Game = Model.define(:id, :season, :game_type, :date, :start_time, :state, :schedule_state, :ended_in,
      :venue, :neutral_site, :home_team, :away_team, :codes)

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

      # Each coded field's map from NHL codes, and the value an unknown code becomes.
      CODED_FIELDS = {
        game_type: [GAME_TYPES, :other],
        state: [STATES, :unknown],
        schedule_state: [SCHEDULE_STATES, :unknown],
        ended_in: [PERIOD_TYPES, :unknown]
      }.freeze

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
      # @param codes [Hash{Symbol, String => String, Integer}] the NHL's raw codes, keyed by field
      # @raise [ArgumentError] if a field is missing, the wrong type, or not one of its allowed values
      def initialize(id:, season:, game_type:, date:, start_time:, state:, schedule_state:, home_team:,
        away_team:, ended_in: nil, venue: nil, neutral_site: false, codes: {})
        raise ArgumentError, "season must be an Integer, got #{season.inspect}" unless season.is_a?(Integer)
        raise ArgumentError, "neutral_site must be true or false" unless [true, false].include?(neutral_site)

        super(
          id: Identity::PlayerRef.coerce_id(id), season: season,
          game_type: self.class.coerce_coded(:game_type, game_type),
          date: self.class.coerce_date(date), start_time: self.class.coerce_time(start_time),
          state: self.class.coerce_coded(:state, state),
          schedule_state: self.class.coerce_coded(:schedule_state, schedule_state),
          ended_in: ended_in && self.class.coerce_coded(:ended_in, ended_in),
          venue: venue, neutral_site: neutral_site,
          home_team: GameTeam.coerce(home_team), away_team: GameTeam.coerce(away_team),
          codes: self.class.coerce_codes(codes)
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
        # The symbol for one of the NHL's codes.
        #
        # @param field [Symbol] a key of {CODED_FIELDS}
        # @param code [String, Integer, nil] the NHL's code, such as +"OFF"+ or +2+
        # @return [Symbol, nil] the mapped symbol; +:other+ or +:unknown+ for a code not in the map;
        #   +nil+ for a +nil+ code
        # @raise [KeyError] if +field+ isn't a key of {CODED_FIELDS}
        # @example
        #   SportsIngest::NHL::Game.from_code(:state, "CRIT") # => :live
        #   SportsIngest::NHL::Game.from_code(:state, "WARP") # => :unknown
        def from_code(field, code)
          map, fallback = CODED_FIELDS.fetch(field)
          code.nil? ? nil : map.fetch(code, fallback)
        end

        # Whether the gem knows one of the NHL's codes.
        #
        # @param field [Symbol] a key of {CODED_FIELDS}
        # @param code [String, Integer] the NHL's code
        # @return [Boolean]
        # @raise [KeyError] if +field+ isn't a key of {CODED_FIELDS}
        def known_code?(field, code)
          CODED_FIELDS.fetch(field).first.key?(code)
        end

        # @api private
        # @param field [Symbol] a key of {CODED_FIELDS}
        # @param value [Symbol, String]
        # @return [Symbol]
        # @raise [ArgumentError] if it isn't one of the field's symbols or its fallback
        def coerce_coded(field, value)
          map, fallback = CODED_FIELDS.fetch(field)
          allowed = map.values.uniq + [fallback]
          symbol = value.to_s.to_sym if value.is_a?(String) || value.is_a?(Symbol)
          return symbol if allowed.include?(symbol)

          raise ArgumentError, "#{field} must be one of #{allowed.join(", ")}, got #{value.inspect}"
        end

        # @api private
        # @param codes [Hash{Symbol, String => String, Integer}]
        # @return [Hash{Symbol => String, Integer}] sorted by field
        # @raise [ArgumentError] if a key isn't a coded field or a value isn't a String or Integer
        def coerce_codes(codes)
          raise ArgumentError, "codes must be a Hash, got #{codes.class}" unless codes.is_a?(Hash)

          codes.to_h do |field, code|
            field = field.to_sym
            raise ArgumentError, "codes has no field #{field.inspect}" unless CODED_FIELDS.key?(field)
            raise ArgumentError, "codes[:#{field}] must be a String or Integer" unless code.is_a?(String) || code.is_a?(Integer)

            [field, code]
          end.sort.to_h
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
