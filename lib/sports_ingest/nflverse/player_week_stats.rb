# frozen_string_literal: true

module SportsIngest
  module Nflverse
    # One NFL player's stats for one game, from the +stats_player_week_<season>.csv+ file of the
    # +stats_player+ release (ADR 0041).
    #
    # @!attribute [r] player_id
    #   @return [String] the GSIS player ID, such as +"00-0023459"+
    # @!attribute [r] name
    #   @return [String, nil] the display name, such as +"Patrick Mahomes"+
    # @!attribute [r] position
    #   @return [String, nil] such as +"QB"+ or +"WR"+
    # @!attribute [r] team
    #   @return [String, nil] the team's abbreviation the player played for that week, such as +"KC"+
    # @!attribute [r] season
    #   @return [Integer] the season's start year, such as +2025+
    # @!attribute [r] season_type
    #   @return [String] +"REG"+ or +"POST"+
    # @!attribute [r] week
    #   @return [Integer] the week number
    # @!attribute [r] opponent
    #   @return [String, nil] the opponent's abbreviation
    # @!attribute [r] stats
    #   @return [Hash{String => Integer, Float}] every numeric stat column that has a value,
    #     keyed by its nflverse column name, such as +"passing_yards"+; blank and +NA+ cells are
    #     left out
    #
    # @example
    #   row = SportsIngest::Nflverse::PlayerWeekStats # from PlayerStats#weekly
    #   row.stats.fetch("fantasy_points_ppr")
    PlayerWeekStats = Model.define(:player_id, :name, :position, :team, :season, :season_type, :week,
      :opponent, :stats)
  end
end
