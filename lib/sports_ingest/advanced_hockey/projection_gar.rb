# frozen_string_literal: true

module SportsIngest
  module AdvancedHockey
    # One skater's GAR projection for a season, as {ProjectionGarImport} reads it.
    #
    # Every value is in goals above replacement, as exported; a blank or +NA+ cell is +nil+.
    #
    # @!attribute [r] player
    #   @return [String] the player's name as Evolving-Hockey spells it
    # @!attribute [r] season
    #   @return [Integer] the year the season starts in (ADR 0006): +2026+ for 26-27
    # @!attribute [r] teams
    #   @return [Array<String>] team abbreviations in export order, as {SkaterGar} reads them
    # @!attribute [r] position
    #   @return [String] the position as exported, such as +C+, +L+, +R+ or +D+
    # @!attribute [r] gar
    #   @return [Float, nil] projected goals above replacement
    # @!attribute [r] gar_minus
    #   @return [Float, nil] the low end of the projection (GAR−)
    # @!attribute [r] gar_plus
    #   @return [Float, nil] the high end of the projection (GAR+)
    # @!attribute [r] gar_60
    #   @return [Float, nil] projected GAR per 60 minutes of ice time
    # @!attribute [r] uncertainty
    #   @return [Float, nil] the ± on {gar_60}, as exported
    ProjectionGar = Model.define(
      :player, :season, :teams, :position, :gar, :gar_minus, :gar_plus, :gar_60, :uncertainty
    )
  end
end
