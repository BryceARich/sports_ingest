# frozen_string_literal: true

module SportsIngest
  module AdvancedHockey
    # One goalie-season from Evolving-Hockey's goalie GAR table, as {GoalieGarImport} reads it.
    #
    # Every component is in goals above replacement, as exported; a blank or +NA+ cell is +nil+.
    #
    # @!attribute [r] player
    #   @return [String] the player's name as Evolving-Hockey spells it
    # @!attribute [r] season
    #   @return [Integer] the year the season starts in (ADR 0006): +2025+ for 2025-26
    # @!attribute [r] teams
    #   @return [Array<String>] team abbreviations in export order; +N.J/WPG+ is +["N.J", "WPG"]+
    # @!attribute [r] position
    #   @return [String] the position as exported, normally +G+
    # @!attribute [r] gp
    #   @return [Integer, nil] games played
    # @!attribute [r] toi_ev
    #   @return [Float, nil] time on ice at even strength, in minutes
    # @!attribute [r] toi_sh
    #   @return [Float, nil] time on ice shorthanded, in minutes
    # @!attribute [r] fa_ev
    #   @return [Float, nil] shots faced at even strength
    # @!attribute [r] fa_sh
    #   @return [Float, nil] shots faced shorthanded
    # @!attribute [r] evd
    #   @return [Float, nil] even-strength defence (GAR)
    # @!attribute [r] shd
    #   @return [Float, nil] shorthanded defence (GAR)
    # @!attribute [r] take
    #   @return [Float, nil] penalties taken (GAR)
    # @!attribute [r] draw
    #   @return [Float, nil] penalties drawn (GAR)
    # @!attribute [r] gar
    #   @return [Float, nil] goals above replacement
    # @!attribute [r] war
    #   @return [Float, nil] wins above replacement
    # @!attribute [r] spar
    #   @return [Float, nil] standings points above replacement
    GoalieGar = Model.define(
      :player, :season, :teams, :position, :gp, :toi_ev, :toi_sh, :fa_ev, :fa_sh,
      :evd, :shd, :take, :draw, :gar, :war, :spar
    ) do
      # Merges rows for the same player and season into one, as EH's season grouping reports it.
      #
      # Use it on an export grouped by team and season, where a traded goalie has a row per team.
      # Teams are joined in row order and the counting fields are summed (rounded to one decimal);
      # a sum is +nil+ if any part is. Rows that are already one per goalie-season come back
      # unchanged. As with {SkaterGar.combine}, import the season grouping when totals matter: EH
      # leaves short stints out of the team grouping.
      #
      # @param rows [Array<GoalieGar>] rows from {GoalieGarImport}
      # @return [Array<GoalieGar>] one row per player and season, in order of first appearance
      def self.combine(rows)
        GarCombine.call(rows, self)
      end
    end
  end
end
