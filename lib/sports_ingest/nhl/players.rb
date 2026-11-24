# frozen_string_literal: true

module SportsIngest
  module NHL
    # Player details from +/player/{id}/landing+ and game logs from
    # +/player/{id}/game-log/{season}/{gameType}+ (ADR 0023).
    #
    # Results are also written to the processed cache: details under +nhl/players/<id>+ (read
    # with +model: NHL::PlayerDetails+), game logs under
    # +nhl/game_logs/<id>/<season ID>/<regular|playoffs>+ (+model: NHL::GameLogEntry+).
    #
    # @example
    #   players = SportsIngest::NHL::Players.new
    #   mcdavid = players.fetch(8478402)
    #   mcdavid.player.birth_date                       # => #<Date: 1997-01-13>
    #   players.game_log(8478402, season: 2025).sum(&:points)
    #   players.game_log(8478402, season: 2025, game_type: :playoffs)
    #   players.game_log(8478402)                       # the NHL's current season and game type
    class Players
      # Game types a game log can be asked for, and the NHL's code for each.
      GAME_TYPES = {regular: 2, playoffs: 3}.freeze

      # Payload keys of a season or career line, by {StatLine} field.
      STAT_LINE_KEYS = {
        games_played: "gamesPlayed", goals: "goals", assists: "assists", points: "points",
        plus_minus: "plusMinus", pim: "pim", shots: "shots", shooting_pct: "shootingPctg",
        power_play_goals: "powerPlayGoals", power_play_points: "powerPlayPoints",
        shorthanded_goals: "shorthandedGoals", shorthanded_points: "shorthandedPoints",
        game_winning_goals: "gameWinningGoals", ot_goals: "otGoals", faceoff_pct: "faceoffWinningPctg",
        games_started: "gamesStarted", wins: "wins", losses: "losses", ot_losses: "otLosses",
        shutouts: "shutouts", goals_against: "goalsAgainst", shots_against: "shotsAgainst",
        goals_against_avg: "goalsAgainstAvg", save_pct: "savePctg"
      }.freeze

      # Payload keys of a game-log row, by {GameLogEntry} field.
      GAME_LOG_KEYS = {
        goals: "goals", assists: "assists", points: "points", plus_minus: "plusMinus", pim: "pim",
        shots: "shots", shifts: "shifts", power_play_goals: "powerPlayGoals",
        power_play_points: "powerPlayPoints", shorthanded_goals: "shorthandedGoals",
        shorthanded_points: "shorthandedPoints", game_winning_goals: "gameWinningGoals",
        ot_goals: "otGoals", games_started: "gamesStarted", decision: "decision",
        shots_against: "shotsAgainst", goals_against: "goalsAgainst", save_pct: "savePctg",
        shutouts: "shutouts"
      }.freeze

      # A time on ice such as +"21:55"+ or +"7578:38"+.
      TOI = /\A(\d+):([0-5]\d)\z/

      # @param client [Client] what fetches from the NHL
      # @param processed [Cache::Processed, nil] where results are saved; +nil+ skips saving
      def initialize(client: Client.new, processed: Cache::Processed.new)
        @client = client
        @processed = processed
      end

      # One player's bio, draft, career and season totals.
      #
      # @param id [String, Integer] the NHL player ID, such as +8478402+
      # @return [PlayerDetails]
      # @raise [ArgumentError] if +id+ isn't all digits
      # @raise [NotFound] if the NHL has no such player
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      # @raise [HTTPError, ParseError] as {Client#get_json} does
      def fetch(id)
        id = check_id(id)
        response = @client.web_response("player/#{id}/landing")
        details = parse_landing(@client.parse(response))
        @processed&.write("nhl/players/#{id}", [details], source: Client::SOURCE,
          fetched_at: response.fetched_at, model: PlayerDetails)
        details
      end

      # One player's games in one season, oldest first.
      #
      # With no +season+ and no +game_type+, returns the NHL's current log for the player: this
      # season's, or the playoffs' while they're on.
      #
      # @param id [String, Integer] the NHL player ID
      # @param season [Integer, nil] the season's start year (ADR 0006)
      # @param game_type [Symbol, nil] +:regular+ (the default with +season+) or +:playoffs+
      # @return [Array<GameLogEntry>] empty when the player has no games then
      # @raise [ArgumentError] if +id+ isn't all digits, +season+ isn't a start year, +game_type+
      #   isn't a key of {GAME_TYPES}, or +game_type+ is given without +season+
      # @raise [NotFound] if the NHL has no such player
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      # @raise [HTTPError, ParseError] as {Client#get_json} does
      def game_log(id, season: nil, game_type: nil)
        id = check_id(id)
        raise ArgumentError, "game_type needs a season" if season.nil? && !game_type.nil?

        path = if season.nil?
          "now"
        else
          game_type ||= :regular
          code = GAME_TYPES.fetch(game_type) do
            raise ArgumentError, "game_type must be one of #{GAME_TYPES.keys.join(", ")}, got #{game_type.inspect}"
          end
          "#{Season.id(season)}/#{code}"
        end

        response = @client.web_response("player/#{id}/game-log/#{path}")
        entries = parse_game_log(@client.parse(response), player_id: id)
        save_game_log(id, season, game_type, entries, response.fetched_at)
        entries
      end

      # Maps a +/player/{id}/landing+ payload to details.
      #
      # @param payload [Hash] the parsed JSON
      # @return [PlayerDetails]
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      def parse_landing(payload)
        changed!("a player landing should be a JSON object, got #{payload.class}") unless payload.is_a?(Hash)

        id = payload["playerId"]
        career = payload["careerTotals"] || {}
        PlayerDetails.new(
          player: player(payload), active: payload["isActive"] == true, draft: draft(payload["draftDetails"]),
          career_regular_season: stat_line(career["regularSeason"], game_type: :regular),
          career_playoffs: stat_line(career["playoffs"], game_type: :playoffs),
          seasons: array(payload, "seasonTotals", "player #{id}").map { season_line(it) }
        )
      rescue ArgumentError => e
        changed!("player #{id.inspect} doesn't fit the PlayerDetails model: #{e.message}")
      end

      # Maps a game-log payload to entries, oldest first (the NHL sends newest first).
      #
      # @param payload [Hash] the parsed JSON
      # @param player_id [String] the player the log belongs to
      # @return [Array<GameLogEntry>]
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      def parse_game_log(payload, player_id:)
        changed!("a game log should be a JSON object, got #{payload.class}") unless payload.is_a?(Hash)
        # A season the player has no games in comes without "gameLog".
        return [] unless payload.key?("gameLog")

        season = Season.year(payload.fetch("seasonId") { changed!("a game log has no \"seasonId\"") })
        game_type = Game.from_code(:game_type, payload["gameTypeId"])
        array(payload, "gameLog", "player #{player_id}'s game log").map do |row|
          game_log_entry(row, player_id: player_id, season: season, game_type: game_type)
        end.sort_by { [it.date, it.game_id] }
      rescue ArgumentError => e
        changed!("player #{player_id}'s game log doesn't fit the GameLogEntry model: #{e.message}")
      end

      # @return [String]
      def inspect
        "#<#{self.class.name}>"
      end

      private

      def check_id(id)
        string = id.to_s if id.is_a?(String) || id.is_a?(Integer)
        raise ArgumentError, "a player ID must be all digits, got #{id.inspect}" unless /\A\d+\z/.match?(string.to_s)

        string
      end

      def player(payload)
        Player.new(
          ref: Identity::PlayerRef.new(sport: :hockey, canonical_id: payload["playerId"]),
          first_name: localized(payload["firstName"]), last_name: localized(payload["lastName"]),
          position: payload["position"], team: payload["currentTeamAbbrev"],
          sweater_number: payload["sweaterNumber"], shoots_catches: payload["shootsCatches"],
          height_inches: payload["heightInInches"], weight_pounds: payload["weightInPounds"],
          birth_date: payload["birthDate"], birth_city: localized(payload["birthCity"]),
          birth_state_province: localized(payload["birthStateProvince"]),
          birth_country: payload["birthCountry"], headshot: payload["headshot"]
        )
      end

      def draft(details)
        return nil if details.nil?

        Draft.new(year: details["year"], team: details["teamAbbrev"], round: details["round"],
          pick_in_round: details["pickInRound"], overall_pick: details["overallPick"])
      end

      def season_line(row)
        changed!("a season total should be an object, got #{row.class}") unless row.is_a?(Hash)

        stat_line(row, game_type: Game.from_code(:game_type, row["gameTypeId"]),
          season: Season.year(row["season"]), league: row["leagueAbbrev"], team_name: localized(row["teamName"]))
      end

      def stat_line(row, game_type:, **identity)
        return nil if row.nil?
        changed!("a stat line should be an object, got #{row.class}") unless row.is_a?(Hash)

        StatLine.new(game_type: game_type, **identity, **pick(row, STAT_LINE_KEYS),
          avg_toi_seconds: seconds(row["avgToi"]), toi_seconds: seconds(row["timeOnIce"]))
      end

      def game_log_entry(row, player_id:, season:, game_type:)
        changed!("a game-log row should be an object, got #{row.class}") unless row.is_a?(Hash)

        GameLogEntry.new(
          player_id: player_id, game_id: row["gameId"], season: season, game_type: game_type,
          date: row["gameDate"], team: row["teamAbbrev"], opponent: row["opponentAbbrev"],
          home: home?(row["homeRoadFlag"]), toi_seconds: seconds(row["toi"]),
          # Goalie rows say "penaltyMins" in some payloads and "pim" in others.
          **pick(row, GAME_LOG_KEYS), pim: row["pim"] || row["penaltyMins"]
        )
      end

      def save_game_log(id, season, game_type, entries, fetched_at)
        # The "now" log is saved under the season and game type it turned out to be.
        season ||= entries.first&.season
        game_type ||= entries.first&.game_type
        return if @processed.nil? || season.nil?

        @processed.write("nhl/game_logs/#{id}/#{Season.id(season)}/#{game_type}", entries,
          source: Client::SOURCE, fetched_at: fetched_at, model: GameLogEntry)
      end

      def pick(row, keys)
        keys.to_h { |field, key| [field, row[key]] }
      end

      def home?(flag)
        case flag
        when "H" then true
        when "R" then false
        else raise ArgumentError, "homeRoadFlag must be \"H\" or \"R\", got #{flag.inspect}"
        end
      end

      def seconds(toi)
        return nil if toi.nil?

        match = TOI.match(toi) or raise ArgumentError, "time on ice #{toi.inspect} isn't minutes:seconds"
        (match[1].to_i * 60) + match[2].to_i
      end

      def array(payload, key, what)
        rows = payload.fetch(key) { changed!("#{what} has no #{key.inspect}; keys are #{payload.keys.inspect}") }
        changed!("#{what}'s #{key.inspect} should be an array, got #{rows.class}") unless rows.is_a?(Array)

        rows
      end

      # Names come as {"default" => "...", "fr" => "..."}; keep the default.
      def localized(value)
        value.is_a?(Hash) ? value["default"] : value
      end

      def changed!(message)
        raise SourceChangedError.new(message, source: Client::SOURCE)
      end
    end
  end
end
