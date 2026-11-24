# frozen_string_literal: true

module SportsIngest
  module ESPN
    # One player's actual season totals from ESPN's player pool, as raw stat lines. Points are not
    # applied: a league scores these itself.
    #
    # @!attribute [r] player_id
    #   @return [Integer] ESPN's player ID
    # @!attribute [r] full_name
    #   @return [String] such as +"Connor McDavid"+
    # @!attribute [r] pro_team_id
    #   @return [Integer] ESPN's pro team ID (0 for a free agent); see {PlayerPool}
    # @!attribute [r] default_position_id
    #   @return [Integer] ESPN's position ID, as ESPN numbers them
    # @!attribute [r] game
    #   @return [Symbol] +:hockey+ or +:football+
    # @!attribute [r] season
    #   @return [Integer] the season's start year (ADR 0006)
    # @!attribute [r] stats
    #   @return [Hash{String => Numeric}] ESPN's stat IDs (as strings, such as +"13"+) and their
    #     values, exactly as sent
    #
    # @example
    #   line = SportsIngest::ESPN::PlayerPool.new(game: :hockey).actual_stats(last: 1).first
    #   [line.full_name, line.stats]
    PlayerStats = Model.define(:player_id, :full_name, :pro_team_id, :default_position_id, :game, :season,
      :stats)
  end
end
