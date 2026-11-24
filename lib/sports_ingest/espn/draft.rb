# frozen_string_literal: true

module SportsIngest
  module ESPN
    # A league's draft for one season, from the +mDraftDetail+ view (built by {Drafts}).
    #
    # +picks+ are sorted by +overall_pick+ and are {DraftPick} models; keepers are included in
    # that order, flagged by +keeper+ (see {#keepers}).
    #
    # @!attribute [r] season
    #   @return [Integer] ESPN's season ID, as {Client#season} takes it
    # @!attribute [r] drafted
    #   @return [Boolean] whether ESPN marks the draft as having happened
    # @!attribute [r] in_progress
    #   @return [Boolean] whether the draft is running now
    # @!attribute [r] picks
    #   @return [Array<DraftPick>]
    #
    # @example
    #   draft = SportsIngest::ESPN::Drafts.new.history(12_345, season: 2026)
    #   draft.keepers.map(&:player_id)
    Draft = Model.define(:season, :drafted, :in_progress, :picks) do
      # @param picks [Array<DraftPick, Hash>] picks, as models or hashes
      # @raise [ArgumentError] as {Model} does
      def initialize(picks: [], **fields)
        super(picks: picks.map { |pick| DraftPick.coerce(pick) }, **fields)
      end

      # @return [Array<DraftPick>] the picks flagged as keepers, in draft order
      def keepers
        picks.select(&:keeper)
      end
    end
  end
end
