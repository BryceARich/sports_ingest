# frozen_string_literal: true

module SportsIngest
  module Nflverse
    # A release asset on disk, as returned by {ReleaseDownloader#fetch}.
    #
    # @!attribute [r] path
    #   @return [Pathname] where the file is
    # @!attribute [r] tag
    #   @return [String] the release tag, e.g. +"stats_player"+
    # @!attribute [r] file
    #   @return [String] the asset name, e.g. +"stats_player_week_2025.csv"+
    # @!attribute [r] url
    #   @return [String] the download URL
    # @!attribute [r] last_updated
    #   @return [String] the tag's +timestamp.json+ +last_updated+ value this copy matches,
    #     e.g. +"2026-11-22 05:12:43 EST"+
    # @!attribute [r] fetched_at
    #   @return [Time] when this copy was downloaded
    # @!attribute [r] stale
    #   @return [Boolean] +true+ if the network failed, so this copy couldn't be checked against
    #     upstream (or replaced by a newer one)
    ReleaseFile = Data.define(:path, :tag, :file, :url, :last_updated, :fetched_at, :stale) do
      # @return [Boolean] whether this copy couldn't be checked because the network failed
      def stale? = stale
    end
  end
end
