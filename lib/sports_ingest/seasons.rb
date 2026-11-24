# frozen_string_literal: true

module SportsIngest
  # Resolves the +seasons:+ / +last:+ keywords every span-of-seasons method takes (ADR 0006).
  # Sources work out their own current season (such as {NHL::Season.current}) and pass it in.
  #
  # @example
  #   SportsIngest::Seasons.resolve(last: 3, current: 2026)               # => [2024, 2025, 2026]
  #   SportsIngest::Seasons.resolve(seasons: [2025, 2023], current: 2026) # => [2023, 2025]
  #   SportsIngest::Seasons.resolve(current: 2026, default_last: 3)       # => [2024, 2025, 2026]
  module Seasons
    # The start years a call asked for, oldest first.
    #
    # @param seasons [Array<Integer>, nil] an explicit list of start years
    # @param last [Integer, nil] the N most recent seasons, counting +current+
    # @param current [Integer] the source's current season's start year
    # @param default_last [Integer, nil] +last+ to use when neither keyword is given; +nil+ means
    #   one of them is required
    # @return [Array<Integer>] unique start years, oldest first
    # @raise [ArgumentError] if both or (without +default_last+) neither keyword is given,
    #   +seasons+ isn't a non-empty Array of Integers, or +last+ isn't a positive Integer
    def self.resolve(current:, seasons: nil, last: nil, default_last: nil)
      raise ArgumentError, "pass seasons: or last:, not both" if seasons && last
      raise ArgumentError, "current must be an Integer start year, got #{current.inspect}" unless current.is_a?(Integer)

      unless seasons
        last ||= default_last or raise ArgumentError, "pass seasons: [2024, 2025] or last: N"
        raise ArgumentError, "last must be a positive Integer, got #{last.inspect}" unless last.is_a?(Integer) && last.positive?

        return ((current - last + 1)..current).to_a
      end

      unless seasons.is_a?(Array) && !seasons.empty? && seasons.all?(Integer)
        raise ArgumentError, "seasons must be a non-empty Array of start years such as [2024, 2025], got #{seasons.inspect}"
      end

      seasons.uniq.sort
    end
  end
end
