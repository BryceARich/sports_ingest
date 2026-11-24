# frozen_string_literal: true

require "date"

module SportsIngest
  module NHL
    # Converts between the gem's season names and the NHL's (ADR 0006): the gem names a season by
    # the year it starts in, the NHL by both years as eight digits.
    #
    # @example
    #   SportsIngest::NHL::Season.id(2025)          # => "20252026"
    #   SportsIngest::NHL::Season.year("20252026")  # => 2025
    module Season
      # The first NHL season, 1917-18.
      FIRST = 1917

      # An NHL season ID: a start year followed by the next year.
      ID = /\A(\d{4})(\d{4})\z/

      # The month a new season becomes current: the regular season starts in October. Until then
      # the season that ended in the spring is still current, so +last: N+ in the summer counts
      # it rather than a season with no games.
      ROLLOVER_MONTH = 10

      # The current season on a date (ADR 0024).
      #
      # @param today [Date] the date to judge by; pass one in specs to keep them deterministic
      # @return [Integer] the start year, such as +2026+ for any date from 2026-10-01 to 2027-09-30
      # @raise [ArgumentError] if +today+ isn't a Date
      # @example
      #   SportsIngest::NHL::Season.current(Date.new(2026, 11, 23)) # => 2026
      #   SportsIngest::NHL::Season.current(Date.new(2027, 7, 1))   # => 2026
      def self.current(today = Date.today)
        raise ArgumentError, "today must be a Date, got #{today.inspect}" unless today.is_a?(Date)

        (today.month >= ROLLOVER_MONTH) ? today.year : today.year - 1
      end

      # The NHL's ID for a season.
      #
      # @param year [Integer] the year the season starts in
      # @return [String] such as +"20252026"+
      # @raise [ArgumentError] if +year+ isn't an Integer from {FIRST} to 9998
      def self.id(year)
        unless year.is_a?(Integer) && year.between?(FIRST, 9998)
          raise ArgumentError, "season must be a start year from #{FIRST} on, such as 2025, got #{year.inspect}"
        end

        "#{year}#{year + 1}"
      end

      # The start year of an NHL season ID.
      #
      # @param id [String, Integer] such as +"20252026"+ or +20252026+
      # @return [Integer] such as +2025+
      # @raise [ArgumentError] if +id+ isn't two consecutive years
      def self.year(id)
        match = ID.match(id.to_s)
        unless match && match[2].to_i == match[1].to_i + 1
          raise ArgumentError, "#{id.inspect} isn't an NHL season ID such as \"20252026\""
        end

        match[1].to_i
      end
    end
  end
end
