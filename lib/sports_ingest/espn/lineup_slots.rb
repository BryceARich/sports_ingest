# frozen_string_literal: true

module SportsIngest
  module ESPN
    # ESPN Fantasy lineup slot IDs, per sport: the keys of a league's +lineupSlotCounts+ and of a
    # scoring item's +pointsOverrides+, and the values in a player's +eligibleSlots+. Slots not
    # listed here are unknown and get a +"slot_<id>"+ name (+docs/sources/espn.md+).
    #
    # @example
    #   SportsIngest::ESPN::LineupSlots.name_for(:football, 23) # => "FLEX"
    #   SportsIngest::ESPN::LineupSlots.name_for(:hockey, 42)   # => "slot_42"
    module LineupSlots
      # Football (+ffl+) slots.
      FOOTBALL = {
        0 => "QB", 2 => "RB", 3 => "RB/WR", 4 => "WR", 5 => "WR/TE", 6 => "TE", 7 => "OP",
        8 => "DT", 9 => "DE", 10 => "LB", 11 => "DL", 12 => "CB", 13 => "S", 14 => "DB", 15 => "DP",
        16 => "D/ST", 17 => "K", 18 => "P", 20 => "BE", 21 => "IR", 23 => "FLEX"
      }.freeze

      # Hockey (+fhl+) slots.
      HOCKEY = {
        0 => "C", 1 => "LW", 2 => "RW", 3 => "F", 4 => "D", 5 => "G", 6 => "UTIL", 7 => "BE", 8 => "IR"
      }.freeze

      # Slot tables by ESPN's game segment.
      BY_GAME = {"ffl" => FOOTBALL, "fhl" => HOCKEY}.freeze

      module_function

      # The slot table for a sport.
      #
      # @param game [Symbol, String] +:hockey+ / +:fhl+ or +:football+ / +:ffl+
      # @return [Hash{Integer => String}] slot ID to name, frozen
      # @raise [ArgumentError] for an unknown game
      def for(game)
        BY_GAME.fetch(StatIds.segment(game))
      end

      # @param game [Symbol, String] as {.for}
      # @param id [Integer, String] a slot ID; Strings like ESPN's JSON keys work too
      # @return [String] the slot's name, or +"slot_<id>"+ for an unknown slot
      # @raise [ArgumentError] for an unknown game, or an ID that isn't an integer
      def name_for(game, id)
        id = Integer(id)
        self.for(game).fetch(id) { "slot_#{id}" }
      end
    end
  end
end
