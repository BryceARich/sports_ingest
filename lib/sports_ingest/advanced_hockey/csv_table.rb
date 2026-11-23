# frozen_string_literal: true

require "csv"

module SportsIngest
  module AdvancedHockey
    # Reads a manually exported CSV table into rows keyed by normalized column names (ADR 0044).
    #
    # Headers are matched loosely: case, surrounding space and punctuation don't matter, so
    # +EVO_GAR+, +EVO GAR+ and +evo-gar+ all become +:evo_gar+. Columns the caller doesn't ask for
    # are ignored, and rows whose cells are all blank (common at the end of a spreadsheet export)
    # are skipped.
    #
    # @api private Used by the importers, such as {SkaterGarImport}.
    module CsvTable
      module_function

      # Reads a CSV file as UTF-8, dropping a byte-order mark if there is one.
      #
      # @param path [String] the file to read; +~+ is expanded
      # @return [String] the file's text
      # @raise [NotFound] if the file doesn't exist
      # @raise [Error] if the file can't be read
      def read(path)
        File.read(File.expand_path(path), encoding: "bom|utf-8")
      rescue Errno::ENOENT
        raise NotFound.new("no such file: #{path}", source: SOURCE)
      rescue SystemCallError, IOError => e
        raise Error.new("can't read #{path}: #{e.message}", source: SOURCE)
      end

      # Parses CSV text into rows.
      #
      # @param text [String] the CSV, header row first
      # @param table [String] the table's name, used in error messages
      # @param required [Array<Symbol>] normalized column names that must be present
      # @return [Array<TableRow>] the non-blank rows, in file order
      # @raise [ParseError] if the text isn't valid CSV
      # @raise [SourceChangedError] if a required column is missing
      def rows(text, table:, required:)
        csv = CSV.parse(text.delete_prefix("\uFEFF"), headers: true, header_converters: ->(h) { normalize(h) })
        missing = required - csv.headers
        unless missing.empty?
          raise SourceChangedError.new(
            "#{table}: missing column(s) #{missing.join(", ")}; found #{csv.headers.compact.join(", ")}",
            source: SOURCE
          )
        end

        csv.each.with_index(2).filter_map do |row, line|
          next if row.fields.all? { |cell| cell.to_s.strip.empty? }

          TableRow.new(row.to_h, table: table, line: line)
        end
      rescue CSV::MalformedCSVError => e
        raise ParseError.new("#{table}: #{e.message}", source: SOURCE)
      end

      # Normalizes a header cell: +"EVO GAR"+ and +"EVO_GAR"+ both become +:evo_gar+.
      #
      # @param header [String, nil] the raw header
      # @return [Symbol, nil] the normalized name, or +nil+ for a blank header
      def normalize(header)
        name = header.to_s.downcase.gsub(/[^a-z0-9]+/, "_").delete_prefix("_").delete_suffix("_")
        name.empty? ? nil : name.to_sym
      end
    end
  end
end
