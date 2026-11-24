# frozen_string_literal: true

module SportsIngest
  module Nflverse
    # Loads every player in nflverse's +players.csv+ (the +players+ release, M5-03).
    #
    # The file is downloaded through {ReleaseDownloader}, so it's reused until upstream changes
    # (ADR 0040). Rows with a blank +gsis_id+ are skipped: a player without one has no canonical
    # ID to key on. A +gsis_id+ that isn't in nflverse's format is a changed source.
    #
    # Results are also written to the processed cache under +nflverse/players+ (read with
    # +model: Nflverse::Player+).
    #
    # @example
    #   players = SportsIngest::Nflverse::Players.new.fetch
    #   players.find { it.id == "00-0028830" }.display_name # => "Isaako Aaitui"
    class Players
      # The release tag and asset that hold the file.
      TAG = "players"

      # The asset name within {TAG}.
      FILE = "players.csv"

      # Columns the file must have.
      REQUIRED = %w[gsis_id display_name first_name last_name position birth_date college_name
        latest_team status last_season].freeze

      # @param downloader [ReleaseDownloader, #fetch] downloads the file
      # @param processed [Cache::Processed, nil] where results are saved; +nil+ skips saving
      def initialize(downloader: ReleaseDownloader.new, processed: Cache::Processed.new)
        @downloader = downloader
        @processed = processed
      end

      # Every player with a +gsis_id+, in file order.
      #
      # @return [Array<Player>]
      # @raise [NotFound, HTTPError, ParseError, SourceChangedError] as {ReleaseDownloader#fetch}
      #   and {CsvReader.rows} do, or if a row's +gsis_id+ or birth date isn't valid
      def fetch
        release = @downloader.fetch(TAG, FILE)
        players = CsvReader.rows(release, required: REQUIRED).filter_map { parse_row(it) }
        @processed&.write("nflverse/players", players, source: :nflverse, fetched_at: release.fetched_at,
          model: Player)
        players
      end

      # @return [String]
      def inspect
        "#<#{self.class.name}>"
      end

      private

      def parse_row(row)
        gsis_id = CsvReader.text(row["gsis_id"])
        return nil if gsis_id.nil?

        Player.new(
          ref: Identity::PlayerRef.new(sport: :football, canonical_id: gsis_id),
          display_name: CsvReader.text(row["display_name"]),
          first_name: CsvReader.text(row["first_name"]),
          last_name: CsvReader.text(row["last_name"]),
          position: CsvReader.text(row["position"]),
          birth_date: CsvReader.text(row["birth_date"]),
          college: CsvReader.text(row["college_name"]),
          latest_team: CsvReader.text(row["latest_team"]),
          status: CsvReader.text(row["status"]),
          last_season: CsvReader.integer(row["last_season"])
        )
      rescue ArgumentError => e
        raise SourceChangedError.new("player #{gsis_id.inspect} in #{FILE} doesn't fit the Player model: #{e.message}",
          source: :nflverse)
      end
    end
  end
end
