# frozen_string_literal: true

module SportsIngest
  module NHL
    # One side of a {Game}: the team and, once the game has started, its score.
    #
    # @!attribute [r] id
    #   @return [String] the NHL team ID, such as +"10"+
    # @!attribute [r] tri_code
    #   @return [String] such as +"TOR"+
    # @!attribute [r] score
    #   @return [Integer, nil] goals, or +nil+ before the game starts
    GameTeam = Model.define(:id, :tri_code, :score)

    # Reopened so methods resolve inside the class.
    class GameTeam
      # @param id [String, Integer] the NHL team ID
      # @param tri_code [String] the NHL tri-code
      # @param score [Integer, nil] goals so far
      # @raise [ArgumentError] if +id+ or +tri_code+ is blank, or +score+ isn't a non-negative Integer
      def initialize(id:, tri_code:, score: nil)
        if !score.nil? && !(score.is_a?(Integer) && !score.negative?)
          raise ArgumentError, "score must be a non-negative Integer or nil, got #{score.inspect}"
        end

        super(id: Identity::PlayerRef.coerce_id(id), tri_code: Team.coerce_text(:tri_code, tri_code), score: score)
      end

      # The team from the gem's team table ({Teams}).
      #
      # @return [Team, nil] +nil+ for a team the table doesn't have, such as an all-star side
      def team
        Teams.find_by_source_id(:nhl, id)
      end
    end
  end
end
