# frozen_string_literal: true

module SportsIngest
  module Nflverse
    # One row of a season's roster file from nflverse's +rosters+ release (M5-03): a player on a
    # team in a season, with the position and number they were listed with.
    #
    # A player who changed teams in a season can have more than one entry. Fields the file leaves
    # blank are +nil+.
    #
    # @!attribute [r] ref
    #   @return [Identity::PlayerRef] the canonical ID
    # @!attribute [r] season
    #   @return [Integer] the season's start year, such as +2025+
    # @!attribute [r] team
    #   @return [String, nil] the team code, such as +GB+
    # @!attribute [r] position
    #   @return [String, nil]
    # @!attribute [r] jersey_number
    #   @return [Integer, nil]
    # @!attribute [r] status
    #   @return [String, nil] nflverse's status code, such as +ACT+ or +RES+
    # @!attribute [r] full_name
    #   @return [String, nil]
    #
    # @example
    #   entry = SportsIngest::Nflverse::Rosters.new.fetch(2025).first
    #   entry.id       # => "00-0038389"
    #   entry.team     # => "PIT"
    RosterEntry = Model.define(:ref, :season, :team, :position, :jersey_number, :status, :full_name)

    # Reopened so the initializer can check the ref is a football ref.
    class RosterEntry
      # @param ref [Identity::PlayerRef, Hash] a football ref whose canonical ID is the +gsis_id+
      # @param fields [Hash{Symbol => Object}] the other fields, as listed on the class
      # @raise [ArgumentError] if +ref+ isn't a football ref
      def initialize(ref:, **fields)
        ref = Identity::PlayerRef.coerce(ref)
        raise ArgumentError, "ref must be a football PlayerRef, got #{ref&.sport.inspect}" unless ref&.sport == :football

        super
      end

      # @return [String] the nflverse +gsis_id+, which is the canonical ID
      def id
        ref.canonical_id
      end
    end
  end
end
