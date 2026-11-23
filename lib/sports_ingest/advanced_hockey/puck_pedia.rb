# frozen_string_literal: true

require "csv"

module SportsIngest
  module AdvancedHockey
    # Reads contracts from PuckPedia cap-hit exports: files you export yourself, never downloaded
    # (ADR 0005).
    #
    # Each export layout has its own parser in {FORMATS}; {.contracts} picks the one whose columns
    # the file has, so older layouts can be read for history (ADR 0047).
    #
    # @example
    #   contracts = SportsIngest::AdvancedHockey::PuckPedia.contracts("~/exports/2026-CAPHIT.csv")
    #   contracts.first.cap_hit # => 18000000
    module PuckPedia
      # Parsers by format name, newest first. Detection tries them in this order.
      FORMATS = {cap_hit_2026: CapHit2026}.freeze

      # Loads every contract in a cap-hit export.
      #
      # @param path [String, Pathname] the exported CSV
      # @param format [Symbol, nil] a key of {FORMATS}; +nil+ detects it from the header row
      # @return [Array<Contract>] one per player row, in file order
      # @raise [NotFound] if +path+ doesn't exist
      # @raise [ParseError] if the file isn't readable UTF-8 CSV
      # @raise [SourceChangedError] if no format matches the header, or a row's values don't fit it
      # @raise [ArgumentError] if +format+ isn't a key of {FORMATS}
      def self.contracts(path, format: nil)
        parser = format && FORMATS.fetch(format) do
          raise ArgumentError, "unknown format #{format.inspect}; known: #{FORMATS.keys.join(", ")}"
        end
        table = read(path)
        parser ||= detect(table.headers, path)
        parser.parse(table, file: File.basename(path))
      end

      # The format whose required columns all appear in +headers+.
      #
      # @param headers [Array<String, nil>] the file's header row
      # @param path [String, Pathname] for the error message
      # @return [Class] a parser from {FORMATS}
      # @raise [SourceChangedError] if none matches
      def self.detect(headers, path)
        FORMATS.each_value { |parser| return parser if parser.missing_columns(headers).empty? }

        newest = FORMATS.first
        raise SourceChangedError.new(
          "#{File.basename(path)} matches no known PuckPedia format; " \
          "the #{newest[0]} format is missing columns #{newest[1].missing_columns(headers).join(", ")}",
          source: :puckpedia
        )
      end

      # @api private
      # @param path [String, Pathname]
      # @return [CSV::Table]
      def self.read(path)
        text = File.read(File.expand_path(path), mode: "r:bom|utf-8")
        unless text.valid_encoding?
          raise ParseError.new("#{File.basename(path)} isn't valid UTF-8", source: :puckpedia)
        end

        CSV.parse(text, headers: true)
      rescue Errno::ENOENT
        raise NotFound.new("no PuckPedia export at #{path}", source: :puckpedia)
      rescue SystemCallError => e
        raise Error.new("can't read #{path}: #{e.message}", source: :puckpedia)
      rescue CSV::MalformedCSVError => e
        raise ParseError.new("#{File.basename(path)} isn't valid CSV: #{e.message}", source: :puckpedia)
      end
      private_class_method :read
    end
  end
end
