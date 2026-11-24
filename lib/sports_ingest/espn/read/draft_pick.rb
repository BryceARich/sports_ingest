# frozen_string_literal: true

module SportsIngest
  module ESPN
    module Read
      # One pick in a fantasy draft (part of {Draft}).
      #
      # +team_id+ is the fantasy team's ID inside its league, not an NHL team code; +player_id+ is
      # ESPN's player ID, which {Client#get_json} can look up in the player pool.
      #
      # @!attribute [r] overall_pick
      #   @return [Integer] the pick's place in the whole draft, from 1
      # @!attribute [r] round
      #   @return [Integer]
      # @!attribute [r] round_pick
      #   @return [Integer] the pick's place within its round
      # @!attribute [r] team_id
      #   @return [Integer] the ESPN ID of the fantasy team that picked
      # @!attribute [r] player_id
      #   @return [Integer] the ESPN ID of the player picked
      # @!attribute [r] keeper
      #   @return [Boolean] +true+ when the player was kept from a previous season, not drafted
      #
      # @example
      #   draft.picks.first.overall_pick # => 1
      DraftPick = Model.define(:overall_pick, :round, :round_pick, :team_id, :player_id, :keeper)
    end
  end
end
