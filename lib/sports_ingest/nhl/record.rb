# frozen_string_literal: true

module SportsIngest
  module NHL
    # A team's record over a split of its games: home, road or the last 10 (part of {Standing}).
    #
    # @!attribute [r] games_played
    #   @return [Integer]
    # @!attribute [r] wins
    #   @return [Integer] all wins, including overtime and shootout wins
    # @!attribute [r] losses
    #   @return [Integer] regulation losses
    # @!attribute [r] ot_losses
    #   @return [Integer] overtime and shootout losses
    # @!attribute [r] points
    #   @return [Integer]
    # @!attribute [r] regulation_wins
    #   @return [Integer]
    # @!attribute [r] regulation_plus_ot_wins
    #   @return [Integer] wins not decided by a shootout
    # @!attribute [r] goals_for
    #   @return [Integer]
    # @!attribute [r] goals_against
    #   @return [Integer]
    Record = Model.define(:games_played, :wins, :losses, :ot_losses, :points, :regulation_wins,
      :regulation_plus_ot_wins, :goals_for, :goals_against)

    # Reopened so methods resolve inside the class.
    class Record
      # Payload key suffixes, after the split's prefix (+home+, +road+, +l10+), for each field.
      KEYS = {games_played: "GamesPlayed", wins: "Wins", losses: "Losses", ot_losses: "OtLosses",
              points: "Points", regulation_wins: "RegulationWins",
              regulation_plus_ot_wins: "RegulationPlusOtWins", goals_for: "GoalsFor",
              goals_against: "GoalsAgainst"}.freeze

      # @return [Integer] goals for minus goals against
      def goal_differential = goals_for - goals_against
    end
  end
end
