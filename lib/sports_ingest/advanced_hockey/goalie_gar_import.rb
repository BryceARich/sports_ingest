# frozen_string_literal: true

module SportsIngest
  module AdvancedHockey
    # Imports Evolving-Hockey's goalie GAR table from a manually exported CSV (ADR 0044).
    #
    # Rows come back one model per row, in file order. Extra columns are ignored; a missing one
    # raises {SourceChangedError}, as does a cell that doesn't fit its column.
    #
    # @example
    #   require "sports_ingest/advanced_hockey"
    #   rows = SportsIngest::AdvancedHockey::GoalieGarImport.read("~/hockey/goalie_gar.csv")
    #   rows.first.teams # => ["N.J", "WPG"]
    #   rows.first.gar   # => 1.2
    module GoalieGarImport
      # The table's name in error messages.
      TABLE = "goalie GAR"

      # Columns read as Floats, in model order.
      FLOAT_COLUMNS = %i[
        toi_ev toi_sh fa_ev fa_sh evd shd take draw gar war spar
      ].freeze

      # Every column the export must have, by normalized name ({CsvTable.normalize}).
      COLUMNS = (%i[player season team position gp] + FLOAT_COLUMNS).freeze

      module_function

      # Imports a goalie GAR CSV file.
      #
      # @param path [String] the exported file; +~+ is expanded
      # @return [Array<GoalieGar>] one per non-blank row, in file order
      # @raise [NotFound] if the file doesn't exist
      # @raise [ParseError] if the file isn't valid CSV
      # @raise [SourceChangedError] if a column is missing or a cell doesn't fit its column
      def read(path)
        parse(CsvTable.read(path))
      end

      # Imports goalie GAR rows from CSV text.
      #
      # @param text [String] the CSV, header row first
      # @return [Array<GoalieGar>] one per non-blank row, in file order
      # @raise [ParseError] if the text isn't valid CSV
      # @raise [SourceChangedError] if a column is missing or a cell doesn't fit its column
      def parse(text)
        CsvTable.rows(text, table: TABLE, required: COLUMNS).map do |row|
          GoalieGar.new(
            player: row.string(:player),
            season: row.season(:season),
            teams: row.list(:team),
            position: row.string(:position),
            gp: row.integer(:gp),
            **FLOAT_COLUMNS.to_h { |column| [column, row.float(column)] }
          )
        end
      end
    end
  end
end
