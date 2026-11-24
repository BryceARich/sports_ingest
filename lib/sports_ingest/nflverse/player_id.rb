# frozen_string_literal: true

module SportsIngest
  module Nflverse
    # One player's IDs across sources, from the +players+ release (ADR 0043).
    #
    # @!attribute [r] gsis_id
    #   @return [String] the GSIS player ID nflverse keys everything by, such as +"00-0023459"+
    # @!attribute [r] name
    #   @return [String, nil] the display name
    # @!attribute [r] position
    #   @return [String, nil] such as +"QB"+ or +"WR"+
    # @!attribute [r] ids
    #   @return [Hash{String => String}] the player's ID in each source that has one, keyed by
    #     source name (+"espn"+, +"sleeper"+, +"pfr"+); sources the player has no ID for are left out
    #
    # @example
    #   player = SportsIngest::Nflverse::IdMap.new.players.first
    #   player.ids.fetch("espn") # => "4241479"
    PlayerId = Model.define(:gsis_id, :name, :position, :ids)
  end
end
