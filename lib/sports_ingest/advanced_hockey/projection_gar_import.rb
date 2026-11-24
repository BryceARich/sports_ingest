# frozen_string_literal: true

module SportsIngest
  module AdvancedHockey
    # Imports Evolving-Hockey's GAR projection tab from a manually exported CSV (ADR 0044).
    #
    # The tab's signs are kept in the column names: +GAR-+ and +GAR+ are the low and high ends of
    # the projection, +GAR/60-+ and +GAR/60+ the same per 60 minutes, and +GAR Unc+ the
    # uncertainty. A missing column raises {SourceChangedError}, as does a cell that doesn't fit
    # its column.
    #
    # @example
    #   require "sports_ingest/advanced_hockey"
    #   rows = SportsIngest::AdvancedHockey::ProjectionGarImport.read("~/hockey/GAR_Proj_26-27.csv")
    #   rows.first.season # => 2026
    #   rows.first.gar    # => 1.8
    module ProjectionGarImport
      # The table's name in error messages.
      TABLE = "GAR projections"

      # Raw headers whose signs or slashes would otherwise collapse into a duplicate name.
      ALIASES = {
        "GAR-" => :gar_minus,
        "GAR+" => :gar_plus,
        "GAR/60-" => :gar_60_minus,
        "GAR/60+" => :gar_60_plus,
        "GAR UNC" => :uncertainty
      }.freeze

      # Columns read as Floats, in model order.
      FLOAT_COLUMNS = %i[
        toi_all evo evd ppo shd take draw gar gar_minus gar_plus gar_60 gar_60_minus gar_60_plus
        uncertainty
      ].freeze

      # Every column the export must have, by normalized name ({CsvTable.normalize} or {ALIASES}).
      COLUMNS = (%i[player season team position] + FLOAT_COLUMNS).freeze

      module_function

      # Imports a GAR projection CSV file.
      #
      # @param path [String] the exported file; +~+ is expanded
      # @return [Array<ProjectionGar>] one per non-blank row, in file order
      # @raise [NotFound] if the file doesn't exist
      # @raise [ParseError] if the file isn't valid CSV
      # @raise [SourceChangedError] if a column is missing or a cell doesn't fit its column
      def read(path)
        parse(CsvTable.read(path))
      end

      # Imports GAR projection rows from CSV text.
      #
      # @param text [String] the CSV, header row first
      # @return [Array<ProjectionGar>] one per non-blank row, in file order
      # @raise [ParseError] if the text isn't valid CSV
      # @raise [SourceChangedError] if a column is missing or a cell doesn't fit its column
      def parse(text)
        CsvTable.rows(text, table: TABLE, required: COLUMNS, aliases: ALIASES).map do |row|
          ProjectionGar.new(
            player: row.string(:player),
            season: row.season(:season),
            teams: row.list(:team),
            position: row.string(:position),
            **FLOAT_COLUMNS.to_h { |column| [column, row.float(column)] }
          )
        end
      end
    end
  end
end
