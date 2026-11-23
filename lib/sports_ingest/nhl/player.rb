# frozen_string_literal: true

require "date"

module SportsIngest
  module NHL
    # One NHL player as a roster lists them: identity, position and bio.
    #
    # +ref+ carries the canonical ID, which for hockey is the NHL player ID (ADR 0026). Bio fields
    # the NHL leaves out (a sweater number for a player who hasn't worn one yet, a state or
    # province outside North America) are +nil+.
    #
    # @!attribute [r] ref
    #   @return [Identity::PlayerRef] the canonical ID and per-source IDs
    # @!attribute [r] first_name
    #   @return [String]
    # @!attribute [r] last_name
    #   @return [String]
    # @!attribute [r] position
    #   @return [String] one of {POSITIONS}: +C+, +L+, +R+, +D+ or +G+
    # @!attribute [r] team
    #   @return [String, nil] the NHL tri-code of the team whose roster listed the player
    # @!attribute [r] sweater_number
    #   @return [Integer, nil]
    # @!attribute [r] shoots_catches
    #   @return [String, nil] +L+ or +R+
    # @!attribute [r] height_inches
    #   @return [Integer, nil]
    # @!attribute [r] weight_pounds
    #   @return [Integer, nil]
    # @!attribute [r] birth_date
    #   @return [Date, nil]
    # @!attribute [r] birth_city
    #   @return [String, nil]
    # @!attribute [r] birth_state_province
    #   @return [String, nil] such as +AB+; usually only for Canada and the US
    # @!attribute [r] birth_country
    #   @return [String, nil] a three-letter code, such as +CAN+
    # @!attribute [r] headshot
    #   @return [String, nil] the headshot image URL
    #
    # @example
    #   player = SportsIngest::NHL::Rosters.new.fetch("EDM").first
    #   player.id          # => "8478402"
    #   player.full_name   # => "Connor McDavid"
    #   player.forward?    # => true
    #   player.birth_date  # => #<Date: 1997-01-13>
    Player = Model.define(:ref, :first_name, :last_name, :position, :team, :sweater_number,
      :shoots_catches, :height_inches, :weight_pounds, :birth_date, :birth_city,
      :birth_state_province, :birth_country, :headshot)

    # Reopened so constants and methods resolve inside the class.
    class Player
      # NHL position codes.
      POSITIONS = %w[C L R D G].freeze

      # Position codes that are forwards.
      FORWARDS = %w[C L R].freeze

      # @param ref [Identity::PlayerRef, Hash] a hockey ref
      # @param position [String] one of {POSITIONS}
      # @param birth_date [Date, String, nil] a Date or an ISO 8601 date such as +"1997-01-13"+
      # @param fields [Hash{Symbol => Object}] the other fields, as listed on the class
      # @raise [ArgumentError] if +ref+ isn't a hockey ref, a name is blank, +position+ isn't one
      #   of {POSITIONS}, or +birth_date+ isn't a date
      def initialize(ref:, first_name:, last_name:, position:, birth_date:, **fields)
        ref = Identity::PlayerRef.coerce(ref)
        raise ArgumentError, "ref must be a hockey PlayerRef, got #{ref&.sport.inspect}" unless ref&.sport == :hockey
        raise ArgumentError, "position must be one of #{POSITIONS.join(", ")}, got #{position.inspect}" unless POSITIONS.include?(position)

        super(ref: ref, first_name: Team.coerce_text(:first_name, first_name),
              last_name: Team.coerce_text(:last_name, last_name), position: position,
              birth_date: self.class.coerce_date(birth_date), **fields)
      end

      # @return [String] the NHL player ID, which is the canonical ID
      def id
        ref.canonical_id
      end

      # @return [String] first and last name, such as +"Connor McDavid"+
      def full_name
        "#{first_name} #{last_name}"
      end

      # @return [Boolean] true for a centre or winger
      def forward?
        FORWARDS.include?(position)
      end

      # @return [Boolean] true for a defenceman
      def defense?
        position == "D"
      end

      # @return [Boolean] true for a goalie
      def goalie?
        position == "G"
      end

      # @api private
      # @param value [Date, String, nil]
      # @return [Date, nil]
      # @raise [ArgumentError] if +value+ isn't a Date, an ISO 8601 date String or +nil+
      def self.coerce_date(value)
        case value
        when Date, nil then value
        when String then Date.iso8601(value)
        else raise ArgumentError, "birth_date must be a Date or ISO 8601 String, got #{value.class}"
        end
      rescue Date::Error
        raise ArgumentError, "birth_date #{value.inspect} isn't an ISO 8601 date"
      end
    end
  end
end
