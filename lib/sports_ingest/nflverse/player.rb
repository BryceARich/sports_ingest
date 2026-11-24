# frozen_string_literal: true

require "date"

module SportsIngest
  module Nflverse
    # One player from nflverse's +players.csv+ (M5-03).
    #
    # +ref+ carries the canonical ID, which for football is the nflverse +gsis_id+ (ADR 0026).
    # Fields the file leaves blank are +nil+.
    #
    # @!attribute [r] ref
    #   @return [Identity::PlayerRef] the canonical ID
    # @!attribute [r] display_name
    #   @return [String, nil]
    # @!attribute [r] first_name
    #   @return [String, nil]
    # @!attribute [r] last_name
    #   @return [String, nil]
    # @!attribute [r] position
    #   @return [String, nil] nflverse's position code, such as +RB+ or +DL+
    # @!attribute [r] birth_date
    #   @return [Date, nil]
    # @!attribute [r] college
    #   @return [String, nil]
    # @!attribute [r] latest_team
    #   @return [String, nil] the team code the player last appeared for, such as +WAS+
    # @!attribute [r] status
    #   @return [String, nil] nflverse's status code, such as +ACT+ or +DEV+
    # @!attribute [r] last_season
    #   @return [Integer, nil]
    #
    # @example
    #   player = SportsIngest::Nflverse::Players.new.fetch.first
    #   player.id           # => "00-0028830"
    #   player.display_name # => "Isaako Aaitui"
    Player = Model.define(:ref, :display_name, :first_name, :last_name, :position, :birth_date,
      :college, :latest_team, :status, :last_season)

    # Reopened so the initializer can coerce the ref and birth date.
    class Player
      # @param ref [Identity::PlayerRef, Hash] a football ref whose canonical ID is the +gsis_id+
      # @param birth_date [Date, String, nil] a Date or an ISO 8601 date
      # @param fields [Hash{Symbol => Object}] the other fields, as listed on the class
      # @raise [ArgumentError] if +ref+ isn't a football ref or +birth_date+ isn't a date
      def initialize(ref:, birth_date:, **fields)
        ref = Identity::PlayerRef.coerce(ref)
        raise ArgumentError, "ref must be a football PlayerRef, got #{ref&.sport.inspect}" unless ref&.sport == :football

        super(ref: ref, birth_date: coerce_date(birth_date), **fields)
      end

      # @return [String] the nflverse +gsis_id+, which is the canonical ID
      def id
        ref.canonical_id
      end

      private

      def coerce_date(value)
        return value if value.nil? || value.is_a?(Date)

        Date.iso8601(value.to_s)
      rescue Date::Error
        raise ArgumentError, "birth_date must be an ISO 8601 date, got #{value.inspect}"
      end
    end
  end
end
