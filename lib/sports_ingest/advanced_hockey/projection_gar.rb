# frozen_string_literal: true

module SportsIngest
  module AdvancedHockey
    # One skater's GAR projection for a season, as {ProjectionGarImport} reads it.
    #
    # Values are in goals above replacement, as exported (components in the same units as
    # {SkaterGar}); a blank or +NA+ cell is +nil+.
    #
    # @!attribute [r] player
    #   @return [String] the player's name as Evolving-Hockey spells it
    # @!attribute [r] season
    #   @return [Integer] the year the season starts in (ADR 0006): +2026+ for 26-27
    # @!attribute [r] teams
    #   @return [Array<String>] team abbreviations in export order, as {SkaterGar} reads them
    # @!attribute [r] position
    #   @return [String] the position as exported, such as +C+, +L+, +R+ or +D+
    # @!attribute [r] toi_all
    #   @return [Float, nil] time on ice in all situations, in minutes
    # @!attribute [r] evo
    #   @return [Float, nil] even-strength offence
    # @!attribute [r] evd
    #   @return [Float, nil] even-strength defence
    # @!attribute [r] ppo
    #   @return [Float, nil] power-play offence
    # @!attribute [r] shd
    #   @return [Float, nil] shorthanded defence
    # @!attribute [r] take
    #   @return [Float, nil] penalties taken
    # @!attribute [r] draw
    #   @return [Float, nil] penalties drawn
    # @!attribute [r] gar
    #   @return [Float, nil] projected goals above replacement
    # @!attribute [r] gar_minus
    #   @return [Float, nil] the low end of the projection (GAR-)
    # @!attribute [r] gar_plus
    #   @return [Float, nil] the high end of the projection (GAR+)
    # @!attribute [r] gar_60
    #   @return [Float, nil] projected GAR per 60 minutes of ice time
    # @!attribute [r] gar_60_minus
    #   @return [Float, nil] the low end of {gar_60} (GAR/60-)
    # @!attribute [r] gar_60_plus
    #   @return [Float, nil] the high end of {gar_60} (GAR/60+)
    # @!attribute [r] uncertainty
    #   @return [Float, nil] the uncertainty of the projection (GAR Unc)
    ProjectionGar = Model.define(
      :player, :season, :teams, :position, :toi_all, :evo, :evd, :ppo, :shd, :take, :draw,
      :gar, :gar_minus, :gar_plus, :gar_60, :gar_60_minus, :gar_60_plus, :uncertainty
    )
  end
end
