# frozen_string_literal: true

module SportsIngest
  module AdvancedHockey
    # Imports Evolving-Hockey's GAR projection tab from a manually exported CSV (ADR 0044).
    #
    # The tab has no season column of its own, so the caller names the season it projects. A
    # missing column raises {SourceChangedError}, as does a cell that doesn't fit its column.
    #
    # @example
    #   require "sports_ingest/advanced_hockey"
    #   rows = SportsIngest::AdvancedHockey::ProjectionGarImport.read("~/hockey/GAR_Proj_26-27.csv", season: 2026)
    #   rows.first.gar # => 1.8
    module ProjectionGarImport
      # The table's name in error messages.
      TABLE = "GAR projections"

      # Columns read as Floats, in model order.
      FLOAT_COLUMNS = %i[gar gar_minus gar_plus gar_60 uncertainty].freeze

      # Every column the export must have, by normalized name ({CsvTable.normalize}).
      #
      # PLACEHOLDER: these header names are not confirmed. The GAR_Proj_26-27 tab's real header row
      # has to be checked against this list (see the M6-03 issue) before the importer can be called
      # done.
      COLUMNS = (%i[player team position] + FLOAT_COLUMNS).freeze

      module_function

      # Imports a GAR projection CSV file.
      #
      # @param path [String] the exported file; +~+ is expanded
      # @param season [Integer] the season the projections are for, named by its start year (ADR 0006)
      # @return [Array<ProjectionGar>] one per non-blank row, in file order
      # @raise [NotFound] if the file doesn't exist
      # @raise [ParseError] if the file isn't valid CSV
      # @raise [SourceChangedError] if a column is missing or a cell doesn't fit its column
      def read(path, season:)
        parse(CsvTable.read(path), season: season)
      end

      # Imports GAR projection rows from CSV text.
      #
      # @param text [String] the CSV, header row first
      # @param season [Integer] the season the projections are for, named by its start year
      # @return [Array<ProjectionGar>] one per non-blank row, in file order
      # @raise [ParseError] if the text isn't valid CSV
      # @raise [SourceChangedError] if a column is missing or a cell doesn't fit its column
      def parse(text, season:)
        CsvTable.rows(text, table: TABLE, required: COLUMNS).map do |row|
          ProjectionGar.new(
            player: row.string(:player),
            season: season,
            teams: row.list(:team),
            position: row.string(:position),
            **FLOAT_COLUMNS.to_h { |column| [column, row.float(column)] }
          )
        end
      end
    end
  end
end
