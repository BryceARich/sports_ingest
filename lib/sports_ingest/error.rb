# frozen_string_literal: true

module SportsIngest
  # Base class for every error the gem raises. Rescue this to catch them all.
  #
  # M1-09 builds out the rest of the hierarchy under it.
  #
  # @example
  #   begin
  #     SportsIngest.configure { |c| c.default_ttl = -1 }
  #   rescue SportsIngest::Error => e
  #     warn e.message
  #   end
  class Error < StandardError
  end
end
