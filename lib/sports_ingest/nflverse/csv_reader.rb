# frozen_string_literal: true

require "csv"

module SportsIngest
  module Nflverse
    # Reads an nflverse CSV release file into hashes, with the rules every file shares: a UTF-8
    # byte-order mark is dropped, a blank cell is +nil+, and a missing column is a changed source.
    #
    # @example
    #   rows = SportsIngest::Nflverse::CsvReader.rows(release, required: %w[gsis_id])
    #   rows.first["gsis_id"] # => "00-0028830"
    module CsvReader
      module_function

      # @param release [ReleaseFile] the downloaded file
      # @param required [Array<String>] column names the file must have
      # @return [Array<Hash{String => String, nil}>] one hash per data row, keyed by header
      # @raise [ParseError] if the file isn't CSV
      # @raise [SourceChangedError] if a required column is missing
      def rows(release, required:)
        text = File.read(release.path, encoding: "UTF-8").delete_prefix("﻿")
        table = CSV.parse(text, headers: true)
        missing = required - table.headers.compact
        unless missing.empty?
          raise SourceChangedError.new("#{release.tag}/#{release.file} has no #{missing.join(", ")} column",
            source: :nflverse)
        end

        table.map(&:to_h)
      rescue CSV::MalformedCSVError => e
        raise ParseError.new("#{release.tag}/#{release.file} isn't CSV: #{e.message}", source: :nflverse)
      end

      # @param value [String, nil] a cell
      # @return [String, nil] the cell stripped, or +nil+ if it's blank
      def text(value)
        return nil if value.nil?

        stripped = value.strip
        stripped.empty? ? nil : stripped
      end

      # @param value [String, nil] a cell such as +"69"+
      # @return [Integer, nil] the integer, or +nil+ if the cell is blank or not a whole number
      def integer(value)
        Integer(text(value) || "", exception: false)
      end
    end
  end
end
