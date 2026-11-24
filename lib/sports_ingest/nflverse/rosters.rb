# frozen_string_literal: true

module SportsIngest
  module Nflverse
    # Loads one season's roster from nflverse's +rosters+ release, +roster_<season>.csv+ (M5-03).
    #
    # The file is downloaded through {ReleaseDownloader}, so it's reused until upstream changes
    # (ADR 0040). Rows with a blank +gsis_id+ are skipped, as in {Players}. A +gsis_id+ that isn't
    # in nflverse's format is a changed source.
    #
    # Results are also written to the processed cache under +nflverse/rosters/<season>+ (read with
    # +model: Nflverse::RosterEntry+).
    #
    # @example
    #   entries = SportsIngest::Nflverse::Rosters.new.fetch(2025)
    #   entries.select { it.team == "GB" }.map(&:full_name)
    class Rosters
      # The release tag that holds every season's file.
      TAG = "rosters"

      # Columns the file must have.
      REQUIRED = %w[season team position jersey_number status full_name gsis_id].freeze

      # @param downloader [ReleaseDownloader, #fetch] downloads the file
      # @param processed [Cache::Processed, nil] where results are saved; +nil+ skips saving
      def initialize(downloader: ReleaseDownloader.new, processed: Cache::Processed.new)
        @downloader = downloader
        @processed = processed
      end

      # One season's roster entries, in file order.
      #
      # @param season [Integer] the season's start year, such as +2025+
      # @return [Array<RosterEntry>]
      # @raise [ArgumentError] if +season+ isn't a positive Integer
      # @raise [NotFound, HTTPError, ParseError, SourceChangedError] as {ReleaseDownloader#fetch}
      #   and {CsvReader.rows} do, or if a row's +gsis_id+ isn't valid
      def fetch(season)
        raise ArgumentError, "season must be a positive Integer, got #{season.inspect}" unless season.is_a?(Integer) && season.positive?

        release = @downloader.fetch(TAG, "roster_#{season}.csv")
        entries = CsvReader.rows(release, required: REQUIRED).filter_map { parse_row(it, season, release) }
        @processed&.write("nflverse/rosters/#{season}", entries, source: :nflverse,
          fetched_at: release.fetched_at, model: RosterEntry)
        entries
      end

      # @return [String]
      def inspect
        "#<#{self.class.name}>"
      end

      private

      def parse_row(row, season, release)
        gsis_id = CsvReader.text(row["gsis_id"])
        return nil if gsis_id.nil?

        RosterEntry.new(
          ref: Identity::PlayerRef.new(sport: :football, canonical_id: gsis_id),
          season: season,
          team: CsvReader.text(row["team"]),
          position: CsvReader.text(row["position"]),
          jersey_number: CsvReader.integer(row["jersey_number"]),
          status: CsvReader.text(row["status"]),
          full_name: CsvReader.text(row["full_name"])
        )
      rescue ArgumentError => e
        raise SourceChangedError.new("#{release.file} has a row for #{gsis_id.inspect} that doesn't fit RosterEntry: #{e.message}",
          source: :nflverse)
      end
    end
  end
end
