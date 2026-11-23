# frozen_string_literal: true

module SportsIngest
  # Raised when a source refuses access (HTTP 401 or 403) or its credentials are missing,
  # for example expired ESPN +espn_s2+ / +SWID+ cookies.
  class AuthError < Error
  end
end
