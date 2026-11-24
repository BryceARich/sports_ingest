# frozen_string_literal: true

module SportsIngest
  module Nflverse
    # One NFL player's regular-season totals, from the +stats_player_reg_<season>.csv+ file of the
    # +stats_player+ release (ADR 0041).
    #
    # @!attribute [r] player_id
    #   @return [String] the GSIS player ID, such as +"00-0023459"+
    # @!attribute [r] name
    #   @return [String, nil] the display name
    # @!attribute [r] position
    #   @return [String, nil] such as +"QB"+ or +"WR"+
    # @!attribute [r] team
    #   @return [String, nil] the team's abbreviation in the season's last game, such as +"KC"+
    # @!attribute [r] season
    #   @return [Integer] the season's start year
    # @!attribute [r] stats
    #   @return [Hash{String => Integer, Float}] every numeric stat column that has a value,
    #     keyed by its nflverse column name; blank and +NA+ cells are left out
    #
    # @example
    #   row = SportsIngest::Nflverse::PlayerSeasonStats # from PlayerStats#season
    #   row.stats.fetch("receiving_yards")
    PlayerSeasonStats = Model.define(:player_id, :name, :position, :team, :season, :stats)
  end
end
