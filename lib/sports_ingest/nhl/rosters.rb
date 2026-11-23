# frozen_string_literal: true

module SportsIngest
  module NHL
    # Team rosters from +/roster/{TEAM}/{season}+, as {Player} models.
    #
    # Each roster is also written to the processed cache under
    # +nhl/rosters/<TRI_CODE>/<season ID or "current">+, so consumers can read it with
    # +Cache::Processed#read(key, model: NHL::Player)+.
    #
    # @example
    #   rosters = SportsIngest::NHL::Rosters.new
    #   rosters.fetch("EDM").select(&:goalie?).map(&:full_name)
    #   rosters.fetch("T.B", season: 2024).size   # any source's team code works
    class Rosters
      # The payload's groups, in the order players are returned.
      GROUPS = %w[forwards defensemen goalies].freeze

      # @param client [Client] what fetches from the NHL
      # @param processed [Cache::Processed, nil] where rosters are saved; +nil+ skips saving
      def initialize(client: Client.new, processed: Cache::Processed.new)
        @client = client
        @processed = processed
      end

      # One team's roster: forwards, then defensemen, then goalies, in the NHL's order.
      #
      # @param team [Team, String] a {Team} or any code {Teams.fetch} resolves, such as +"EDM"+
      # @param season [Integer, nil] the year the season starts in (ADR 0006); +nil+ means the
      #   current season
      # @return [Array<Player>] the players; empty when the NHL has no roster for that season
      # @raise [NotFound] if the team code is unknown, or the NHL has no such roster
      # @raise [ArgumentError] if +season+ isn't a valid start year
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      # @raise [HTTPError, ParseError] as {Client#get_json} does
      def fetch(team, season: nil)
        team = team.is_a?(Team) ? team : Teams.fetch(team)
        season_key = season.nil? ? "current" : Season.id(season)
        response = @client.get(@client.url_for("roster/#{team.tri_code}/#{season_key}"))
        players = parse(@client.parse(response), team: team.tri_code)
        @processed&.write("nhl/rosters/#{team.tri_code}/#{season_key}", players, source: Client::SOURCE,
          fetched_at: response.fetched_at, model: Player)
        players
      end

      # Maps a roster payload to players.
      #
      # @param payload [Hash] the parsed +/roster+ JSON
      # @param team [String, nil] the tri-code to record on each player
      # @return [Array<Player>]
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      def parse(payload, team: nil)
        changed!("a roster should be a JSON object, got #{payload.class}") unless payload.is_a?(Hash)
        # The NHL answers {} for a team with no roster that season.
        return [] if payload.empty?

        GROUPS.flat_map do |group|
          rows = payload.fetch(group) { changed!("a roster has no #{group.inspect}; keys are #{payload.keys.inspect}") }
          changed!("roster #{group.inspect} should be an array, got #{rows.class}") unless rows.is_a?(Array)

          rows.map { |row| player(row, team) }
        end
      end

      # @return [String]
      def inspect
        "#<#{self.class.name}>"
      end

      private

      def player(row, team)
        changed!("a roster player should be an object, got #{row.class}") unless row.is_a?(Hash)

        Player.new(
          ref: Identity::PlayerRef.new(sport: :hockey, canonical_id: row["id"]),
          first_name: localized(row["firstName"]), last_name: localized(row["lastName"]),
          position: row["positionCode"], team: team, sweater_number: row["sweaterNumber"],
          shoots_catches: row["shootsCatches"], height_inches: row["heightInInches"],
          weight_pounds: row["weightInPounds"], birth_date: row["birthDate"],
          birth_city: localized(row["birthCity"]), birth_state_province: localized(row["birthStateProvince"]),
          birth_country: row["birthCountry"], headshot: row["headshot"]
        )
      rescue ArgumentError => e
        changed!("roster player #{row["id"].inspect} doesn't fit the Player model: #{e.message}")
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
