# frozen_string_literal: true

module SportsIngest
  module ESPN
    # ESPN Fantasy stat IDs, per sport: what the numbers in a league's scoring settings and in a
    # player's +stats+ mean. ESPN doesn't publish this list; how each entry was checked is in
    # +docs/sources/espn.md+ (ADR 0033 in +docs/adr/0033-espn-league-settings-as-a-plain-hash.md+).
    #
    # Each entry is +id => {abbrev:, name:}+. The abbreviation follows ESPN's scoring page where
    # it has one; abbreviations are unique per sport, so where ESPN reuses one
    # (interceptions thrown and made) the defensive or less used stat gets another. IDs not listed
    # here are unknown, not unused.
    #
    # @example
    #   SportsIngest::ESPN::StatIds.abbrev(:football, 53) # => "REC"
    #   SportsIngest::ESPN::StatIds.description(:hockey, 38) # => "Power-play points"
    #   SportsIngest::ESPN::StatIds.abbrev(:hockey, 999)  # => nil
    module StatIds
      # Football (+ffl+) stat IDs.
      FOOTBALL = {
        0 => {abbrev: "PA", name: "Passing attempts"},
        1 => {abbrev: "PC", name: "Passing completions"},
        2 => {abbrev: "INC", name: "Incomplete passes"},
        3 => {abbrev: "PY", name: "Passing yards"},
        4 => {abbrev: "PTD", name: "Passing touchdowns"},
        19 => {abbrev: "2PC", name: "Two-point passing conversions"},
        20 => {abbrev: "INT", name: "Interceptions thrown"},
        21 => {abbrev: "CMP%", name: "Completion percentage"},
        23 => {abbrev: "RA", name: "Rushing attempts"},
        24 => {abbrev: "RY", name: "Rushing yards"},
        25 => {abbrev: "RTD", name: "Rushing touchdowns"},
        26 => {abbrev: "2PR", name: "Two-point rushing conversions"},
        39 => {abbrev: "YPC", name: "Rushing yards per attempt"},
        41 => {abbrev: "RECS", name: "Receptions (in player stats; leagues score 53)"},
        42 => {abbrev: "REY", name: "Receiving yards"},
        43 => {abbrev: "RETD", name: "Receiving touchdowns"},
        44 => {abbrev: "2PRE", name: "Two-point receiving conversions"},
        53 => {abbrev: "REC", name: "Each reception"},
        58 => {abbrev: "RET", name: "Receiving targets"},
        63 => {abbrev: "FTD", name: "Fumble recovered for a touchdown"},
        64 => {abbrev: "PSK", name: "Times sacked (offense)"},
        68 => {abbrev: "FUM", name: "Fumbles"},
        72 => {abbrev: "FUML", name: "Fumbles lost"},
        73 => {abbrev: "TO", name: "Turnovers"},
        74 => {abbrev: "FG50P", name: "Field goals made, 50+ yards"},
        75 => {abbrev: "FGA50P", name: "Field goals attempted, 50+ yards"},
        76 => {abbrev: "FG50PM", name: "Field goals missed, 50+ yards"},
        77 => {abbrev: "FG40", name: "Field goals made, 40-49 yards"},
        78 => {abbrev: "FGA40", name: "Field goals attempted, 40-49 yards"},
        79 => {abbrev: "FG40M", name: "Field goals missed, 40-49 yards"},
        80 => {abbrev: "FG0", name: "Field goals made, 0-39 yards"},
        81 => {abbrev: "FGA0", name: "Field goals attempted, 0-39 yards"},
        82 => {abbrev: "FG0M", name: "Field goals missed, 0-39 yards"},
        83 => {abbrev: "FG", name: "Field goals made"},
        84 => {abbrev: "FGA", name: "Field goals attempted"},
        85 => {abbrev: "FGM", name: "Field goals missed"},
        86 => {abbrev: "PAT", name: "Extra points made"},
        87 => {abbrev: "PATA", name: "Extra points attempted"},
        88 => {abbrev: "PATM", name: "Extra points missed"},
        89 => {abbrev: "PA0", name: "0 points allowed"},
        90 => {abbrev: "PA1", name: "1-6 points allowed"},
        91 => {abbrev: "PA7", name: "7-13 points allowed"},
        92 => {abbrev: "PA14", name: "14-17 points allowed"},
        93 => {abbrev: "BLKKRTD", name: "Blocked punt or field goal returned for a touchdown"},
        95 => {abbrev: "DINT", name: "Interceptions (defense)"},
        96 => {abbrev: "FR", name: "Fumbles recovered"},
        97 => {abbrev: "BLKK", name: "Blocked kicks"},
        98 => {abbrev: "SF", name: "Safeties"},
        99 => {abbrev: "SK", name: "Sacks"},
        101 => {abbrev: "KRTD", name: "Kickoff return touchdowns"},
        102 => {abbrev: "PRTD", name: "Punt return touchdowns"},
        103 => {abbrev: "INTTD", name: "Interception return touchdowns"},
        104 => {abbrev: "FRTD", name: "Fumble return touchdowns"},
        106 => {abbrev: "FF", name: "Forced fumbles"},
        107 => {abbrev: "TKA", name: "Assisted tackles"},
        108 => {abbrev: "TKS", name: "Solo tackles"},
        109 => {abbrev: "TK", name: "Total tackles"},
        114 => {abbrev: "KR", name: "Kickoff return yards"},
        115 => {abbrev: "PR", name: "Punt return yards"},
        121 => {abbrev: "PA18", name: "18-21 points allowed"},
        122 => {abbrev: "PA22", name: "22-27 points allowed"},
        123 => {abbrev: "PA28", name: "28-34 points allowed"},
        124 => {abbrev: "PA35", name: "35-45 points allowed"},
        125 => {abbrev: "PA46", name: "46+ points allowed"},
        128 => {abbrev: "YA100", name: "Less than 100 total yards allowed"},
        129 => {abbrev: "YA199", name: "100-199 total yards allowed"},
        130 => {abbrev: "YA299", name: "200-299 total yards allowed"},
        131 => {abbrev: "YA349", name: "300-349 total yards allowed"},
        132 => {abbrev: "YA399", name: "350-399 total yards allowed"},
        133 => {abbrev: "YA449", name: "400-449 total yards allowed"},
        134 => {abbrev: "YA499", name: "450-499 total yards allowed"},
        135 => {abbrev: "YA549", name: "500-549 total yards allowed"},
        136 => {abbrev: "YA550", name: "550+ total yards allowed"},
        198 => {abbrev: "FG50", name: "Field goals made, 50-59 yards"},
        199 => {abbrev: "FGA50", name: "Field goals attempted, 50-59 yards"},
        200 => {abbrev: "FG50M", name: "Field goals missed, 50-59 yards"},
        201 => {abbrev: "FG60", name: "Field goals made, 60+ yards"},
        202 => {abbrev: "FGA60", name: "Field goals attempted, 60+ yards"},
        203 => {abbrev: "FG60M", name: "Field goals missed, 60+ yards"},
        206 => {abbrev: "2PTRET", name: "Two-point returns"},
        209 => {abbrev: "1PSF", name: "One-point safeties"},
        210 => {abbrev: "GP", name: "Games played"}
      }.freeze

      # Hockey (+fhl+) stat IDs.
      HOCKEY = {
        0 => {abbrev: "GS", name: "Games started (goalie)"},
        1 => {abbrev: "W", name: "Wins"},
        2 => {abbrev: "L", name: "Losses"},
        3 => {abbrev: "SA", name: "Shots against"},
        4 => {abbrev: "GA", name: "Goals against"},
        6 => {abbrev: "SV", name: "Saves"},
        7 => {abbrev: "SO", name: "Shutouts"},
        8 => {abbrev: "MIN", name: "Goalie time on ice, in seconds"},
        9 => {abbrev: "OTL", name: "Overtime losses"},
        10 => {abbrev: "GAA", name: "Goals-against average"},
        11 => {abbrev: "SV%", name: "Save percentage"},
        13 => {abbrev: "G", name: "Goals"},
        14 => {abbrev: "A", name: "Assists"},
        15 => {abbrev: "+/-", name: "Plus/minus"},
        16 => {abbrev: "PTS", name: "Points"},
        17 => {abbrev: "PIM", name: "Penalty minutes"},
        18 => {abbrev: "PPG", name: "Power-play goals"},
        19 => {abbrev: "PPA", name: "Power-play assists"},
        20 => {abbrev: "SHG", name: "Short-handed goals"},
        21 => {abbrev: "SHA", name: "Short-handed assists"},
        22 => {abbrev: "GWG", name: "Game-winning goals"},
        23 => {abbrev: "FOW", name: "Faceoffs won"},
        24 => {abbrev: "FOL", name: "Faceoffs lost"},
        26 => {abbrev: "TOI", name: "Time on ice, in seconds"},
        27 => {abbrev: "ATOI", name: "Average time on ice, in seconds"},
        28 => {abbrev: "HAT", name: "Hat tricks"},
        29 => {abbrev: "SOG", name: "Shots on goal"},
        30 => {abbrev: "GP", name: "Games played"},
        31 => {abbrev: "HIT", name: "Hits"},
        32 => {abbrev: "BLK", name: "Blocked shots"},
        33 => {abbrev: "DEF", name: "Points by defensemen"},
        35 => {abbrev: "STG", name: "Special-teams goals"},
        36 => {abbrev: "STA", name: "Special-teams assists"},
        37 => {abbrev: "STP", name: "Special-teams points"},
        38 => {abbrev: "PPP", name: "Power-play points"},
        39 => {abbrev: "SHP", name: "Short-handed points"}
      }.freeze

      # Dictionaries by ESPN's game segment.
      BY_GAME = {"ffl" => FOOTBALL, "fhl" => HOCKEY}.freeze

      module_function

      # The dictionary for a sport.
      #
      # @param game [Symbol, String] +:hockey+ / +:fhl+ or +:football+ / +:ffl+, as {Client::GAMES}
      # @return [Hash{Integer => Hash{Symbol => String}}] +id => {abbrev:, name:}+, frozen
      # @raise [ArgumentError] for an unknown game
      def for(game)
        BY_GAME.fetch(segment(game))
      end

      # @param game [Symbol, String] as {.for}
      # @param id [Integer, String] a stat ID; Strings like ESPN's JSON keys work too
      # @return [String, nil] the abbreviation, or +nil+ for an unknown ID
      # @raise [ArgumentError] for an unknown game
      def abbrev(game, id)
        self.for(game).dig(Integer(id, exception: false), :abbrev)
      end

      # @param game [Symbol, String] as {.for}
      # @param id [Integer, String] a stat ID
      # @return [String, nil] what the stat counts, or +nil+ for an unknown ID
      # @raise [ArgumentError] for an unknown game
      def description(game, id)
        self.for(game).dig(Integer(id, exception: false), :name)
      end

      # @param game [Symbol, String] as {.for}
      # @return [String] ESPN's game segment, +"fhl"+ or +"ffl"+
      # @raise [ArgumentError] for an unknown game
      def segment(game)
        Client::GAMES.fetch(game.to_s.downcase.to_sym) do
          raise ArgumentError, "game must be one of #{Client::GAMES.keys.join(", ")}, got #{game.inspect}"
        end
      end
    end
  end
end
