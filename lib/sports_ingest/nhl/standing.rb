# frozen_string_literal: true

module SportsIngest
  module NHL
    # One team's line in the standings on a date (part of {Standings}).
    #
    # @example
    #   car = SportsIngest::NHL::Standings.fetch(date: "2026-11-22").find("CAR")
    #   car.points          # => 39
    #   car.division_rank   # => 1
    #   car.home.wins       # => 8
    #   car.record          # => "18-3-3"
    #
    # @!attribute [r] team_id
    #   @return [String, nil] the NHL team ID from {Teams}, or +nil+ if the team table doesn't know
    #     {#tri_code} (the payload has no ID)
    # @!attribute [r] tri_code
    #   @return [String] such as +"CAR"+
    # @!attribute [r] team_name
    #   @return [String] such as +"Carolina Hurricanes"+
    # @!attribute [r] conference
    #   @return [String] such as +"Eastern"+
    # @!attribute [r] division
    #   @return [String] such as +"Metropolitan"+
    # @!attribute [r] league_rank
    #   @return [Integer] 1 is first in the league
    # @!attribute [r] conference_rank
    #   @return [Integer]
    # @!attribute [r] division_rank
    #   @return [Integer]
    # @!attribute [r] wildcard_rank
    #   @return [Integer, nil] place in the conference's wild-card race; +nil+ for a team in its
    #     division's top three (the NHL sends 0)
    # @!attribute [r] clinch_indicator
    #   @return [String, nil] the NHL's clinch letter (+"x"+, +"y"+, +"z"+, +"p"+, +"e"+), or +nil+
    # @!attribute [r] games_played
    #   @return [Integer]
    # @!attribute [r] wins
    #   @return [Integer] all wins, including overtime and shootout wins
    # @!attribute [r] losses
    #   @return [Integer] regulation losses
    # @!attribute [r] ot_losses
    #   @return [Integer] overtime and shootout losses
    # @!attribute [r] ties
    #   @return [Integer] always 0 since 2005-06
    # @!attribute [r] points
    #   @return [Integer]
    # @!attribute [r] point_pct
    #   @return [Float] points over points available, such as +0.8125+
    # @!attribute [r] regulation_wins
    #   @return [Integer] the first tiebreaker
    # @!attribute [r] regulation_plus_ot_wins
    #   @return [Integer] wins not decided by a shootout
    # @!attribute [r] shootout_wins
    #   @return [Integer]
    # @!attribute [r] shootout_losses
    #   @return [Integer]
    # @!attribute [r] goals_for
    #   @return [Integer]
    # @!attribute [r] goals_against
    #   @return [Integer]
    # @!attribute [r] goal_differential
    #   @return [Integer]
    # @!attribute [r] streak_code
    #   @return [String, nil] +"W"+, +"L"+ or +"OT"+; +nil+ before a team's first game
    # @!attribute [r] streak_count
    #   @return [Integer, nil]
    # @!attribute [r] home
    #   @return [Record] home games
    # @!attribute [r] road
    #   @return [Record] road games
    # @!attribute [r] last_10
    #   @return [Record] the last 10 games
    Standing = Model.define(:team_id, :tri_code, :team_name, :conference, :division, :league_rank,
      :conference_rank, :division_rank, :wildcard_rank, :clinch_indicator, :games_played, :wins,
      :losses, :ot_losses, :ties, :points, :point_pct, :regulation_wins, :regulation_plus_ot_wins,
      :shootout_wins, :shootout_losses, :goals_for, :goals_against, :goal_differential,
      :streak_code, :streak_count, :home, :road, :last_10)

    # Reopened so methods resolve inside the class.
    class Standing
      # Payload keys for the Integer fields read directly from a standings row.
      COUNTS = {league_rank: "leagueSequence", conference_rank: "conferenceSequence",
                division_rank: "divisionSequence", games_played: "gamesPlayed", wins: "wins",
                losses: "losses", ot_losses: "otLosses", ties: "ties", points: "points",
                regulation_wins: "regulationWins", regulation_plus_ot_wins: "regulationPlusOtWins",
                shootout_wins: "shootoutWins", shootout_losses: "shootoutLosses",
                goals_for: "goalFor", goals_against: "goalAgainst",
                goal_differential: "goalDifferential"}.freeze

      # Payload prefixes for the {Record} splits.
      SPLITS = {home: "home", road: "road", last_10: "l10"}.freeze

      # @param home [Record, Hash] home games
      # @param road [Record, Hash] road games
      # @param last_10 [Record, Hash] the last 10 games
      # @param fields [Hash{Symbol => Object}] the other attributes
      def initialize(home:, road:, last_10:, **fields)
        super(home: Record.coerce(home), road: Record.coerce(road), last_10: Record.coerce(last_10), **fields)
      end

      # @return [String] wins, regulation losses and overtime losses, such as +"18-3-3"+
      def record = "#{wins}-#{losses}-#{ot_losses}"

      # @return [Boolean] whether the team has clinched a playoff spot or better
      def clinched? = !clinch_indicator.nil? && clinch_indicator != "e"

      # @return [Boolean] whether the team is eliminated from the playoffs
      def eliminated? = clinch_indicator == "e"

      class << self
        # Builds a standing from one row of the web API's +/standings/{date}+ payload.
        #
        # @param row [Hash{String => Object}] one entry of the payload's +standings+
        # @return [Standing]
        # @raise [SourceChangedError] if a field is missing or the wrong type
        def from_payload(row)
          raise SourceChangedError.new("NHL standings row isn't an object", source: :nhl) unless row.is_a?(Hash)

          tri_code = localized(row, "teamAbbrev")
          new(
            team_id: Teams.find(tri_code, source: :nhl)&.id,
            tri_code: tri_code,
            team_name: localized(row, "teamName"),
            conference: string(row, "conferenceName"),
            division: string(row, "divisionName"),
            wildcard_rank: integer(row, "wildcardSequence").then { |rank| rank.zero? ? nil : rank },
            clinch_indicator: optional_string(row, "clinchIndicator"),
            point_pct: number(row, "pointPctg").to_f,
            streak_code: optional_string(row, "streakCode"),
            streak_count: row["streakCount"].nil? ? nil : integer(row, "streakCount"),
            **COUNTS.transform_values { |key| integer(row, key) },
            **SPLITS.transform_values { |prefix| split(row, prefix) }
          )
        end

        private

        def split(row, prefix)
          Record.new(**Record::KEYS.transform_values { |suffix| integer(row, "#{prefix}#{suffix}") })
        end

        def fetch!(row, key)
          row.fetch(key) { raise SourceChangedError.new("NHL standings row has no #{key.inspect}", source: :nhl) }
        end

        def integer(row, key)
          typed(row, key, Integer)
        end

        def number(row, key)
          typed(row, key, Numeric)
        end

        def string(row, key)
          typed(row, key, String)
        end

        def optional_string(row, key)
          row[key].nil? ? nil : string(row, key)
        end

        def localized(row, key)
          value = fetch!(row, key)
          value = value["default"] if value.is_a?(Hash)
          return value if value.is_a?(String) && !value.empty?

          raise SourceChangedError.new("NHL standings #{key} has no default name", source: :nhl)
        end

        def typed(row, key, type)
          value = fetch!(row, key)
          return value if value.is_a?(type)

          raise SourceChangedError.new("NHL standings #{key} should be #{type}, got #{value.class}", source: :nhl)
        end
      end
    end
  end
end
