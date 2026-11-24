# frozen_string_literal: true

module SportsIngest
  module NHL
    # Where a player was drafted (part of {PlayerDetails}).
    #
    # @!attribute [r] year
    #   @return [Integer] the draft year, such as +2015+
    # @!attribute [r] team
    #   @return [String] the drafting team's NHL tri-code at the time, such as +"EDM"+
    # @!attribute [r] round
    #   @return [Integer]
    # @!attribute [r] pick_in_round
    #   @return [Integer]
    # @!attribute [r] overall_pick
    #   @return [Integer]
    #
    # @example
    #   SportsIngest::NHL::Players.new.fetch(8478402).draft.overall_pick # => 1
    Draft = Model.define(:year, :team, :round, :pick_in_round, :overall_pick)
  end
end
