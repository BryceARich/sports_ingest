# frozen_string_literal: true

module SportsIngest
  module AdvancedHockey
    # Imports Evolving-Hockey's skater GAR table from a manually exported CSV (ADR 0044).
    #
    # Rows come back one model per row, in file order. Extra columns are ignored; a missing one
    # raises {SourceChangedError}, as does a cell that doesn't fit its column.
    #
    # @example
    #   require "sports_ingest/advanced_hockey"
    #   rows = SportsIngest::AdvancedHockey::SkaterGarImport.read("~/hockey/GAR_25-26.csv")
    #   rows.first.teams # => ["VAN", "MIN"]
    #   rows.first.gar   # => 12.4
    module SkaterGarImport
      # The table's name in error messages.
      TABLE = "skater GAR"

      # Columns read as Floats, in model order.
      FLOAT_COLUMNS = %i[
        toi_all evo_gar evd_gar ppo_gar shd_gar take_gar draw_gar
        off_gar def_gar pens_gar gar war spar
      ].freeze

      # Every column the export must have, by normalized name ({CsvTable.normalize}).
      COLUMNS = (%i[player season team position gp] + FLOAT_COLUMNS).freeze

      module_function

      # Imports a skater GAR CSV file.
      #
      # @param path [String] the exported file; +~+ is expanded
      # @return [Array<SkaterGar>] one per non-blank row, in file order
      # @raise [NotFound] if the file doesn't exist
      # @raise [ParseError] if the file isn't valid CSV
      # @raise [SourceChangedError] if a column is missing or a cell doesn't fit its column
      def read(path)
        parse(CsvTable.read(path))
      end

      # Imports a skater GAR CSV file and matches its players to canonical IDs, printing the rows
      # that need a look (ADR 0030).
      #
      # A row with one team is matched on that team; a traded player's row lists several, so it's
      # matched on name and position only. Rows are combined per player and season first.
      #
      # @param path [String] the exported file; +~+ is expanded
      # @param matcher [Identity::Matcher] built from the known players, such as NHL rosters
      # @param io [#puts, nil] where the report is printed; +nil+ prints nothing
      # @return [Identity::UnmatchedReport] every row's match, with the ones needing review
      # @raise [NotFound] if the file doesn't exist
      # @raise [ParseError] if the file isn't valid CSV
      # @raise [SourceChangedError] if a column is missing or a cell doesn't fit its column
      # @example
      #   report = SportsIngest::AdvancedHockey::SkaterGarImport.report("~/hockey/GAR.csv", matcher: matcher)
      #   report.review.size # => 3
      def report(path, matcher:, io: $stdout)
        records = SkaterGar.combine(read(path)).map do |row|
          {source: :evolving_hockey, name: row.player, position: row.position,
           team: (row.teams.one? ? row.teams.first : nil)}
        end
        result = Identity::UnmatchedReport.build(matcher, records)
        io&.print(result.to_text)
        result
      end

      # Imports skater GAR rows from CSV text.
      #
      # @param text [String] the CSV, header row first
      # @return [Array<SkaterGar>] one per non-blank row, in file order
      # @raise [ParseError] if the text isn't valid CSV
      # @raise [SourceChangedError] if a column is missing or a cell doesn't fit its column
      def parse(text)
        CsvTable.rows(text, table: TABLE, required: COLUMNS).map do |row|
          SkaterGar.new(
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
