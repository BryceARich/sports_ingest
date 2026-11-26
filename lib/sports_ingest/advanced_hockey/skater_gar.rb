# frozen_string_literal: true

module SportsIngest
  module AdvancedHockey
    # One skater-season from Evolving-Hockey's skater GAR table, as {SkaterGarImport} reads it.
    #
    # Every component is in goals above replacement, as exported; a blank or +NA+ cell is +nil+.
    #
    # @!attribute [r] player
    #   @return [String] the player's name as Evolving-Hockey spells it
    # @!attribute [r] season
    #   @return [Integer] the year the season starts in (ADR 0006): +2025+ for 2025-26
    # @!attribute [r] teams
    #   @return [Array<String>] team abbreviations in export order; +VAN/MIN+ is +["VAN", "MIN"]+
    # @!attribute [r] position
    #   @return [String] the position as exported, such as +C+, +L+, +R+ or +D+
    # @!attribute [r] gp
    #   @return [Integer, nil] games played
    # @!attribute [r] toi_all
    #   @return [Float, nil] time on ice in all situations, in minutes
    # @!attribute [r] evo_gar
    #   @return [Float, nil] even-strength offence
    # @!attribute [r] evd_gar
    #   @return [Float, nil] even-strength defence
    # @!attribute [r] ppo_gar
    #   @return [Float, nil] power-play offence
    # @!attribute [r] shd_gar
    #   @return [Float, nil] shorthanded defence
    # @!attribute [r] take_gar
    #   @return [Float, nil] penalties taken
    # @!attribute [r] draw_gar
    #   @return [Float, nil] penalties drawn
    # @!attribute [r] off_gar
    #   @return [Float, nil] offence
    # @!attribute [r] def_gar
    #   @return [Float, nil] defence
    # @!attribute [r] pens_gar
    #   @return [Float, nil] penalties
    # @!attribute [r] gar
    #   @return [Float, nil] goals above replacement
    # @!attribute [r] war
    #   @return [Float, nil] wins above replacement
    # @!attribute [r] spar
    #   @return [Float, nil] standings points above replacement
    SkaterGar = Model.define(
      :player, :season, :teams, :position, :gp, :toi_all,
      :evo_gar, :evd_gar, :ppo_gar, :shd_gar, :take_gar, :draw_gar,
      :off_gar, :def_gar, :pens_gar, :gar, :war, :spar
    ) do
      # Merges rows for the same player and season into one, as EH's season grouping reports it.
      #
      # Use it on an export grouped by team and season, where a traded player has a row per
      # team. Teams are joined in row order and the counting fields are summed (rounded to one
      # decimal, like the export); a sum is +nil+ if any part is. Rows that are already one per
      # player-season come back unchanged, so it's safe on either grouping.
      #
      # A combined row can differ from the season grouping's row for the same player: each part
      # was rounded before summing (off by about 0.1), and EH leaves short stints out of the team
      # grouping (a team and its games go missing). Import the season grouping when totals matter.
      #
      # @param rows [Array<SkaterGar>] rows from {SkaterGarImport}
      # @return [Array<SkaterGar>] one row per player and season, in order of first appearance
      # @example
      #   by_team = SkaterGarImport.read("~/hockey/gar_by_team.csv")
      #   SkaterGar.combine(by_team).find { it.player == "Avery Testwood" }.teams # => ["N.J", "WPG"]
      def self.combine(rows)
        GarCombine.call(rows, self)
      end
    end
  end
end
