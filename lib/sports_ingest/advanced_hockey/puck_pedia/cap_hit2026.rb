# frozen_string_literal: true

module SportsIngest
  module AdvancedHockey
    module PuckPedia
      # Parser for the cap-hit layout PuckPedia exports from 2026 on ("2026-CAPHIT").
      #
      # Reads the contract columns and ignores any others, so a sheet that adds stat columns
      # beside them still loads. Rows with a blank +Player+ (spacer or helper rows) are skipped.
      module CapHit2026
        # Field to export column.
        COLUMNS = {
          player: "Player",
          age: "Age",
          position: "Pos",
          status: "Status",
          length: "Length",
          cap_hit: "Cap Hit",
          start_season: "Start Year",
          expiry_season: "Expiry Year",
          expiry_status: "Expiry Status",
          agent: "Signing Agent",
          signing_gm: "Signing GM"
        }.freeze

        # Positions the export uses.
        POSITIONS = %w[C L R D G].freeze

        # Columns this format needs that +headers+ lacks.
        #
        # @param headers [Array<String, nil>]
        # @return [Array<String>] empty when the file has every column
        def self.missing_columns(headers)
          COLUMNS.values - headers.compact
        end

        # Builds contracts from a parsed export.
        #
        # @param table [CSV::Table] the export, parsed with headers
        # @param file [String] the file's name, for error messages
        # @return [Array<Contract>]
        # @raise [SourceChangedError] if a column is missing or a value doesn't fit the format
        def self.parse(table, file:)
          missing = missing_columns(table.headers)
          raise SourceChangedError.new("#{file} is missing columns #{missing.join(", ")}", source: :puckpedia) if missing.any?

          table.each.with_index(2).filter_map do |row, line|
            values = COLUMNS.transform_values { |column| row[column].to_s.strip.then { |v| v unless v.empty? } }
            Row.new(values, "#{file} line #{line}").contract if values[:player]
          end
        end
      end
    end
  end
end
