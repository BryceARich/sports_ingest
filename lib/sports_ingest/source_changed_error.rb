# frozen_string_literal: true

module SportsIngest
  # Raised when a payload parses but its shape is unexpected (a missing key, a renamed column),
  # which usually means the source changed. Adapters raise this instead of returning partial data.
  class SourceChangedError < Error
  end
end
