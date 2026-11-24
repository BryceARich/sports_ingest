# frozen_string_literal: true

module SportsIngest
  module Identity
    # The records of one import that the matcher couldn't resolve with confidence (ADR 0030):
    # unmatched ones and low-confidence ones, each with the players it could be.
    #
    # Build it from the matcher and the import's records, then print it ({#to_text}) or save it
    # ({#to_csv}). A record is one hash of {Matcher#match} arguments, such as
    # +{source: :evolving_hockey, name: "Elias Pettersson", position: "C", team: "VAN"}+.
    #
    # @example
    #   report = SportsIngest::Identity::UnmatchedReport.build(matcher, records)
    #   puts report.to_text
    #   File.write("unmatched.csv", report.to_csv)
    class UnmatchedReport
      # Confidence levels that need a person's look, from {Match::CONFIDENCES}.
      REVIEW = %i[low none].freeze

      # Columns of {#to_csv}, in order.
      CSV_HEADERS = %w[source name id position team confidence reason detail candidates].freeze

      # One record and how it was matched.
      #
      # @!attribute [r] source
      #   @return [Symbol] the source the record came from
      # @!attribute [r] name
      #   @return [String] the name as the source spells it
      # @!attribute [r] id
      #   @return [String, nil] the source's ID for the player, if it has one
      # @!attribute [r] position
      #   @return [String, nil] the position as the source gives it
      # @!attribute [r] team
      #   @return [String, nil] the team as the source gives it
      # @!attribute [r] match
      #   @return [Match] what the matcher decided
      Row = Model.define(:source, :name, :id, :position, :team, :match)

      # @return [Array<Row>] every record, in the order given
      attr_reader :rows

      # Builds a report by matching each record.
      #
      # @param matcher [Matcher] the matcher built from the known players of one sport
      # @param records [Enumerable<Hash>] match arguments per record: +source:+ and +name:+,
      #   plus +id:+, +birth_date:+, +position:+ or +team:+ when the source has them
      # @return [UnmatchedReport]
      # @raise [ArgumentError] as {Matcher#match} does for a malformed record
      # @example
      #   SportsIngest::Identity::UnmatchedReport.build(matcher, [{source: :x, name: "Sebastian Aho"}])
      #     .review.size # => 1
      def self.build(matcher, records)
        rows = records.map do |record|
          args = record.to_h.transform_keys(&:to_sym)
          Row.new(source: args.fetch(:source).to_sym, name: args.fetch(:name), id: args[:id]&.to_s,
            position: args[:position], team: args[:team], match: matcher.match(**args))
        end
        new(rows)
      end

      # @param rows [Array<Row>] the matched records, in order
      def initialize(rows)
        @rows = rows.to_a.freeze
      end

      # @return [Array<Row>] the rows whose confidence is in {REVIEW}, in order
      def review
        rows.select { |row| REVIEW.include?(row.match.confidence) }
      end

      # The report as text for a console.
      #
      # @return [String] a summary line, then one line per row that needs review
      def to_text
        lines = ["Identity report: #{rows.size} records, #{review.size} to review"]
        review.each do |row|
          lines << format_line(row)
        end
        lines.join("\n") + "\n"
      end

      # The rows that need review as CSV, with a header row.
      #
      # @return [String] CSV text (RFC 4180 quoting); the header row is always present
      def to_csv
        lines = [CSV_HEADERS.join(",")]
        review.each do |row|
          match = row.match
          fields = [row.source, row.name, row.id, row.position, row.team, match.confidence, match.reason,
            match.detail, match.candidates.map(&:key).join(" ")]
          lines << fields.map { |field| csv_field(field) }.join(",")
        end
        lines.join("\n") + "\n"
      end

      private

      def format_line(row)
        match = row.match
        target = match.matched? ? "-> #{match.ref.key}" : "unmatched"
        suggestions = match.candidates.empty? ? "" : "  candidates: #{match.candidates.map(&:key).join(", ")}"
        "  [#{match.confidence}] #{row.source} #{row.name}#{" (#{row.position})" if row.position}" \
          "#{" #{row.team}" if row.team}  #{target}  #{match.detail}#{suggestions}"
      end

      def csv_field(value)
        text = value.to_s
        return text unless text.match?(/[",\n]/)

        %("#{text.gsub('"', '""')}")
      end
    end
  end
end
