# frozen_string_literal: true

require "csv"
require "date"

module SportsIngest
  module Nflverse
    # NFL player stats from the +stats_player+ release: one weekly file and one regular-season
    # file per season (ADR 0041).
    #
    # - **Seasons:** +seasons: [2024, 2025]+ or +last: N+ (ADR 0006), +last: 3+ by default, counted
    #   back from the current NFL season. A season starts in one calendar year and ends in the next,
    #   so January and February belong to the year before.
    # - **Files:** the downloads go through {ReleaseDownloader}, so each file is fetched once and
    #   reused until upstream changes. A stale copy (the network failed) is parsed as it is.
    # - **Missing seasons:** a season whose file doesn't exist yet raises {NotFound}; ask for
    #   +seasons:+ without it to skip it.
    # - **Cache:** each season is saved to the processed cache under
    #   +nflverse/player_stats/weekly/<season>+ or +nflverse/player_stats/season/<season>+ (read
    #   with +model: PlayerWeekStats+ or +model: PlayerSeasonStats+).
    #
    # @example
    #   stats = SportsIngest::Nflverse::PlayerStats.new
    #   stats.weekly(last: 3).select { it.week == 1 && it.season == 2025 }
    #   stats.season(seasons: [2025]).max_by { it.stats.fetch("fantasy_points_ppr", 0) }
    class PlayerStats
      # The release tag the files are in.
      TAG = "stats_player"

      # Where the processed cache keeps entries; each season is one key under it.
      CACHE_PREFIX = "nflverse/player_stats"

      # The source name the processed cache records.
      SOURCE = :nflverse

      # How many seasons +last:+ means when neither +seasons:+ nor +last:+ is given.
      DEFAULT_LAST = 3

      # Columns that identify a row or describe it; every other column is a stat.
      ID_COLUMNS = %w[
        player_id player_name player_display_name position position_group headshot_url recent_team
        season season_type week opponent_team
      ].freeze

      # Decimal and integer cells. Anything else ("NA", blank) isn't a stat value.
      NUMBER = /\A-?\d+(?:\.\d+)?(?:e[-+]?\d+)?\z/i

      # @param downloader [ReleaseDownloader, #fetch] fetches the files
      # @param processed [Cache::Processed, nil] where results are saved; +nil+ skips saving
      # @param today [Date, nil] the date the current season is worked out from; +nil+ means today
      def initialize(downloader: ReleaseDownloader.new, processed: Cache::Processed.new, today: nil)
        @downloader = downloader
        @processed = processed
        @today = today
      end

      # Weekly stat lines, one per player per game, including playoff games.
      #
      # @param seasons [Array<Integer>, nil] start years
      # @param last [Integer, nil] the N most recent seasons; +3+ when neither keyword is given
      # @return [Array<PlayerWeekStats>] by season, then week, then player ID
      # @raise [ArgumentError] for bad +seasons+ / +last+ (see {Seasons.resolve})
      # @raise [NotFound] if a season's file doesn't exist
      # @raise [HTTPError] if the network fails and there's no local copy
      # @raise [SourceChangedError] if a file has no +player_id+ or +week+ column
      # @raise [ParseError] if a file isn't CSV
      # @example
      #   stats.weekly(seasons: [2025]).count { it.week == 18 }
      def weekly(seasons: nil, last: nil)
        years(seasons, last).flat_map { weekly_season(it) }
      end

      # Regular-season totals, one per player per season.
      #
      # @param (see #weekly)
      # @return [Array<PlayerSeasonStats>] by season, then player ID
      # @raise (see #weekly)
      # @example
      #   stats.season(last: 3).select { it.stats.fetch("passing_yards", 0) > 4000 }
      def season(seasons: nil, last: nil)
        years(seasons, last).flat_map { season_season(it) }
      end

      # @return [String] a summary that never includes file contents
      def inspect
        "#<#{self.class.name}>"
      end

      private

      def years(seasons, last)
        Seasons.resolve(seasons: seasons, last: last, current: current_season, default_last: DEFAULT_LAST)
      end

      # The NFL season a date falls in: its start year, which is the previous year before March.
      def current_season
        today = @today || Date.today
        (today.month >= 3) ? today.year : today.year - 1
      end

      def weekly_season(year)
        file = "stats_player_week_#{year}.csv"
        release = @downloader.fetch(TAG, file)
        rows = parse_weekly(release.path.read(encoding: Encoding::UTF_8), season: year, file: file)
        @processed&.write("#{CACHE_PREFIX}/weekly/#{year}", rows, source: SOURCE,
          fetched_at: release.fetched_at, model: PlayerWeekStats)
        rows
      end

      def season_season(year)
        file = "stats_player_reg_#{year}.csv"
        release = @downloader.fetch(TAG, file)
        rows = parse_season(release.path.read(encoding: Encoding::UTF_8), season: year, file: file)
        @processed&.write("#{CACHE_PREFIX}/season/#{year}", rows, source: SOURCE,
          fetched_at: release.fetched_at, model: PlayerSeasonStats)
        rows
      end

      def parse_weekly(text, season:, file:)
        table = parse_table(text, file: file, required: %w[player_id week])
        table.filter_map do |row|
          next if blank?(row["player_id"])

          PlayerWeekStats.new(player_id: row["player_id"], name: row["player_display_name"],
            position: row["position"], team: row["recent_team"], season: season,
            season_type: row["season_type"], week: week_of(row, file), opponent: row["opponent_team"],
            stats: stats_of(row))
        end.sort_by { [it.week, it.player_id] }
      end

      def parse_season(text, season:, file:)
        table = parse_table(text, file: file, required: %w[player_id])
        table.filter_map do |row|
          next if blank?(row["player_id"])

          PlayerSeasonStats.new(player_id: row["player_id"], name: row["player_display_name"],
            position: row["position"], team: row["recent_team"], season: season, stats: stats_of(row))
        end.sort_by(&:player_id)
      end

      def parse_table(text, file:, required:)
        table = CSV.parse(text, headers: true)
        missing = required - table.headers
        raise_changed("#{file} has no #{missing.join(" or ")} column") unless missing.empty?

        table
      rescue CSV::MalformedCSVError => e
        raise ParseError.new("#{file} isn't CSV: #{e.message}", source: SOURCE)
      end

      def week_of(row, file)
        cell = row["week"].to_s
        raise_changed("#{file} has a week that isn't a whole number: #{cell.inspect}") unless /\A\d+\z/.match?(cell)

        cell.to_i
      end

      def stats_of(row)
        row.each_with_object({}) do |(column, cell), stats|
          next if column.nil? || ID_COLUMNS.include?(column)

          value = number(cell)
          stats[column] = value unless value.nil?
        end
      end

      def number(cell)
        return nil unless cell && NUMBER.match?(cell)

        (cell.include?(".") || cell.match?(/e/i)) ? cell.to_f : cell.to_i
      end

      def blank?(value)
        value.nil? || value.strip.empty?
      end

      def raise_changed(message)
        raise SourceChangedError.new(message, source: SOURCE)
      end
    end
  end
end
