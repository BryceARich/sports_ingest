# frozen_string_literal: true

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
