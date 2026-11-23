# frozen_string_literal: true

module SportsIngest
  # Raised when the thing asked for doesn't exist: an HTTP 404, or a missing import file.
  class NotFound < Error
  end
end
