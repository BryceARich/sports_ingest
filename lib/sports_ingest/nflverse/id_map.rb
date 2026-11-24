# frozen_string_literal: true

require "csv"

module SportsIngest
  module Nflverse
    # Maps other sources' player IDs (ESPN, Sleeper, PFR) to nflverse's GSIS ID (ADR 0043).
    #
    # - **Source:** the +players.csv+ file of the +players+ release, through {ReleaseDownloader}, so
    #   it's fetched once and reused until upstream changes. A stale copy is parsed as it is.
    # - **Ambiguity:** an ID that two or more GSIS IDs share is left out of the lookup, so
    #   {#gsis_id} returns +nil+ rather than guessing.
    # - **Cache:** the table is saved to the processed cache under +nflverse/id_map+ (read with
    #   +model: PlayerId+).
    #
    # @example
    #   map = SportsIngest::Nflverse::IdMap.new
    #   map.gsis_id(source: "espn", id: "4241479") # => "00-0036389"
    class IdMap
      # The release tag the file is in.
      TAG = "players"

      # The file in that release.
      FILE = "players.csv"

      # Where the processed cache keeps the table.
      CACHE_KEY = "nflverse/id_map"

      # The source name the processed cache records.
      SOURCE = :nflverse

      # Source name to the nflverse column that holds that source's ID.
      ID_COLUMNS = {"espn" => "espn_id", "sleeper" => "sleeper_id", "pfr" => "pfr_id"}.freeze

      # @param downloader [ReleaseDownloader, #fetch] fetches the file
      # @param processed [Cache::Processed, nil] where the table is saved; +nil+ skips saving
      def initialize(downloader: ReleaseDownloader.new, processed: Cache::Processed.new)
        @downloader = downloader
        @processed = processed
      end

      # Every player in the file that has a GSIS ID.
      #
      # @return [Array<PlayerId>] in GSIS ID order
      # @raise [ParseError] if the file isn't CSV
      # @raise [SourceChangedError] if the file has no +gsis_id+ column
      # @raise [HTTPError] if the network fails and there's no local copy
      def players
        @players ||= load_players
      end

      # Looks up the GSIS ID for a player's ID in another source.
      #
      # @param source [String, Symbol] one of {ID_COLUMNS}'s keys, such as +"espn"+
      # @param id [String, Integer, nil] the player's ID in that source
      # @return [String, nil] the GSIS ID; +nil+ if none, if the ID is blank, or if it's shared by
      #   more than one GSIS ID
      # @raise [ArgumentError] if +source+ isn't one of {ID_COLUMNS}'s keys
      # @raise (see #players)
      # @example
      #   map.gsis_id(source: :sleeper, id: "4046")
      def gsis_id(source:, id:)
        name = source.to_s
        raise ArgumentError, "unknown id source #{source.inspect}, use one of #{ID_COLUMNS.keys.join(", ")}" unless ID_COLUMNS.key?(name)

        key = id.to_s.strip
        return nil if key.empty?

        index.fetch(name, {})[key]
      end

      # @return [String] a summary that never includes the table
      def inspect
        "#<#{self.class.name}>"
      end

      private

      def index
        @index ||= ID_COLUMNS.keys.to_h { |source| [source, build_index(source)] }
      end

      def build_index(source)
        owners = Hash.new { |hash, key| hash[key] = [] }
        players.each { |player| (id = player.ids[source]) && owners[id] << player.gsis_id }
        owners.filter_map { |id, gsis_ids| [id, gsis_ids.first] if gsis_ids.uniq.size == 1 }.to_h
      end

      def load_players
        release = @downloader.fetch(TAG, FILE)
        rows = parse(release.path.read(encoding: Encoding::UTF_8))
        @processed&.write(CACHE_KEY, rows, source: SOURCE, fetched_at: release.fetched_at, model: PlayerId)
        rows
      end

      def parse(text)
        table = CSV.parse(text, headers: true)
        raise SourceChangedError.new("#{FILE} has no gsis_id column", source: SOURCE) unless table.headers.include?("gsis_id")

        table.filter_map do |row|
          gsis_id = cell(row["gsis_id"])
          next unless gsis_id

          ids = ID_COLUMNS.filter_map { |source, column| (id = cell(row[column])) && [source, id] }.to_h
          PlayerId.new(gsis_id: gsis_id, name: cell(row["display_name"]), position: cell(row["position"]), ids: ids)
        end.sort_by(&:gsis_id)
      rescue CSV::MalformedCSVError => e
        raise ParseError.new("#{FILE} isn't CSV: #{e.message}", source: SOURCE)
      end

      def cell(value)
        stripped = value.to_s.strip
        stripped.empty? ? nil : stripped
      end
    end
  end
end
