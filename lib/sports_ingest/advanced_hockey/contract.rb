# frozen_string_literal: true

module SportsIngest
  module AdvancedHockey
    # One player's current NHL contract, as listed in a PuckPedia cap-hit export.
    #
    # Seasons are named by the year they start in (ADR 0006): +start_season: 2026+ is 2026-27.
    # Money is whole US dollars. The season-aware view (cap hit per season, clauses, extensions)
    # arrives with M6-05 and will bump +SCHEMA_VERSION+.
    #
    # @!attribute [r] name
    #   @return [String] "First Last", reordered from the export's "Last, First"
    # @!attribute [r] first_name
    #   @return [String]
    # @!attribute [r] last_name
    #   @return [String]
    # @!attribute [r] age
    #   @return [Integer]
    # @!attribute [r] position
    #   @return [String] +"C"+, +"L"+, +"R"+, +"D"+ or +"G"+
    # @!attribute [r] cap_hit
    #   @return [Integer] average annual cap hit, in dollars
    # @!attribute [r] contract_year
    #   @return [Integer] which year of the deal the export's season is (1 for "YR 1 OF 5")
    # @!attribute [r] length
    #   @return [Integer] the deal's length in seasons
    # @!attribute [r] start_season
    #   @return [Integer] the deal's first season
    # @!attribute [r] expiry_season
    #   @return [Integer] the deal's last season
    # @!attribute [r] expiry_status
    #   @return [String] status when it expires, as exported: +"UFA"+, +"RFA"+, +"RFA+ARB"+, ...
    # @!attribute [r] agent
    #   @return [String, nil] the signing agent
    # @!attribute [r] signing_gm
    #   @return [String, nil] the NHL general manager who signed the deal
    Contract = Model.define(
      :name, :first_name, :last_name, :age, :position, :cap_hit, :contract_year, :length,
      :start_season, :expiry_season, :expiry_status, :agent, :signing_gm
    )
  end
end
