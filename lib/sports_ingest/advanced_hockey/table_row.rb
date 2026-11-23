# frozen_string_literal: true

module SportsIngest
  module AdvancedHockey
    # One row of an imported table, with typed readers that raise {SourceChangedError} naming the
    # line and column when a cell doesn't hold what the column should.
    #
    # Blank cells, +NA+ (R's missing value) and +-+ read as +nil+ in the optional readers.
    #
    # @api private Built by {CsvTable.rows}.
    class TableRow
      # Cell values that mean "no value".
      MISSING = ["", "NA", "N/A", "-"].freeze

      # @return [Integer] the row's line number in the file (the header is line 1)
      attr_reader :line

      # @param cells [Hash{Symbol => String, nil}] cells keyed by normalized column name
      # @param table [String] the table's name, used in error messages
      # @param line [Integer] the row's line number in the file
      def initialize(cells, table:, line:)
        @cells = cells
        @table = table
        @line = line
      end

      # @param column [Symbol] normalized column name
      # @return [String] the cell, stripped
      # @raise [SourceChangedError] if the cell is blank
      def string(column)
        value(column) || invalid(column, "a value")
      end

      # @param column [Symbol] normalized column name
      # @return [Integer, nil] the cell as an Integer; a whole decimal such as +82.0+ is accepted
      # @raise [SourceChangedError] if the cell isn't a whole number
      def integer(column)
        number = float(column)
        return nil if number.nil?
        return number.to_i if number == number.to_i

        invalid(column, "a whole number")
      end

      # @param column [Symbol] normalized column name
      # @return [Float, nil] the cell as a Float; thousands separators are ignored
      # @raise [SourceChangedError] if the cell isn't a number
      def float(column)
        text = value(column)
        return nil if text.nil?

        Float(text.delete(","), exception: false) || invalid(column, "a number")
      end

      # Reads a season as the calendar year it starts in (ADR 0006).
      #
      # @param column [Symbol] normalized column name
      # @return [Integer] the start year: +25-26+, +2025-26+, +2025-2026+, +20252026+ and +2025+
      #   all read as +2025+
      # @raise [SourceChangedError] if the cell isn't a season in one of those forms
      def season(column)
        match = SEASON.match(string(column))
        if match
          start = (match[:start].size == 2) ? 2000 + match[:start].to_i : match[:start].to_i
          return start if match[:end].nil? || match[:end].to_i % 100 == (start + 1) % 100
        end
        invalid(column, "a season such as 25-26")
      end

      # @param column [Symbol] normalized column name
      # @return [Array<String>] the cell split on +/+ or +,+: +"VAN/MIN"+ reads as +["VAN", "MIN"]+
      # @raise [SourceChangedError] if the cell is blank
      def list(column)
        string(column).split(%r{[/,]}).map(&:strip).reject(&:empty?)
      end

      # Season spellings: 2025, 25-26, 2025-26, 2025-2026, 2025/26, 20252026.
      SEASON = %r{\A(?:(?<start>\d{4})|(?<start>\d{2}|\d{4})\s*[-/]\s*(?<end>\d{2}|\d{4})|(?<start>\d{4})(?<end>\d{4}))\z}
      private_constant :SEASON

      private

      def value(column)
        text = @cells[column].to_s.strip
        MISSING.include?(text.upcase) ? nil : text
      end

      def invalid(column, expected)
        raise SourceChangedError.new(
          "#{@table} line #{@line}, column #{column}: expected #{expected}, got #{@cells[column].inspect}",
          source: SOURCE
        )
      end
    end
  end
end
