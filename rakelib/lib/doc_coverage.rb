# frozen_string_literal: true

require_relative "error"

module RepoTools
  # Reads the coverage figure out of `yard stats` output and compares it with the threshold
  # (ADR 0015). Parsing the printed summary keeps the check on YARD's own definition of
  # "documented" instead of a second count that could disagree with it.
  class DocCoverage
    # Fail below this share of documented objects, in percent.
    THRESHOLD = 90.0

    # The summary line `yard stats` prints last, e.g. " 92.31% documented".
    SUMMARY = /^\s*(\d+(?:\.\d+)?)% documented\s*$/

    # @param output [String] everything `yard stats` printed
    # @param threshold [Numeric] the minimum documented share, in percent
    def initialize(output, threshold: THRESHOLD)
      @output = output
      @threshold = Float(threshold)
    end

    # @return [Float] the documented share `yard stats` reported, in percent
    # @raise [RepoTools::Error] if the output has no summary line
    def percent
      match = @output.scan(SUMMARY).last
      raise Error, "no \"% documented\" line in the yard stats output" unless match

      Float(match.first)
    end

    # @return [Boolean] true when the documented share is at or above the threshold
    # @raise [RepoTools::Error] if the output has no summary line
    def passing? = percent >= @threshold

    # @return [String] one line saying how the coverage compares with the threshold
    # @raise [RepoTools::Error] if the output has no summary line
    def summary
      verdict = passing? ? "OK" : "below the #{format_percent(@threshold)} threshold"
      "yard: #{format_percent(percent)} documented, #{verdict}"
    end

    private

    def format_percent(value) = format("%.2f%%", value)
  end
end
