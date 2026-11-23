# frozen_string_literal: true

module SportsIngest
  # Raised when a payload or file can't be parsed at all, such as malformed JSON or CSV.
  class ParseError < Error
  end
end
