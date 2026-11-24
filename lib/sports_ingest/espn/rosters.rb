# frozen_string_literal: true

module SportsIngest
  module ESPN
    # A league's teams and their rosters, from ESPN's +mTeam+ and +mRoster+ views (ADR 0037).
    #
    # The result is written to the processed cache under +espn/<game>/leagues/<id>/<season>/teams+,
    # so consumers can read it with +Cache::Processed#read(key, model: ESPN::FantasyTeam)+.
    #
    # @example
    #   rosters = SportsIngest::ESPN::Rosters.new(client: SportsIngest::ESPN::Client.new(game: :hockey))
    #   rosters.fetch(12_345, season: 2027).map { |team| [team.name, team.entries.size] }
    class Rosters
      # The views the league is requested with.
      VIEWS = %w[mTeam mRoster].freeze

      # @param client [Client] what fetches from ESPN
      # @param processed [Cache::Processed, nil] where teams are saved; +nil+ skips saving
      def initialize(client:, processed: Cache::Processed.new)
        @client = client
        @processed = processed
      end

      # One league's teams with their rosters.
      #
      # @param league_id [Integer] the ID in the league's URL
      # @param season [Integer] ESPN's season ID, as in {Client#season}
      # @return [Array<FantasyTeam>] in ESPN's order
      # @raise [ArgumentError] if +league_id+ or +season+ isn't a positive Integer
      # @raise [AuthError] if the league is private and the cookies are missing or rejected
      # @raise [NotFound] if there's no such league
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      # @raise [HTTPError, ParseError] as {Client#get} does
      # @example
      #   SportsIngest::ESPN::Rosters.new(client: client).fetch(12_345, season: 2027)
      def fetch(league_id, season:)
        path = "seasons/#{positive_integer(season, "season")}/segments/0/leagues/" \
          "#{positive_integer(league_id, "league_id")}"
        response = @client.get(path, views: VIEWS)
        teams = parse(@client.parse(response))
        @processed&.write("espn/#{@client.game}/leagues/#{league_id}/#{season}/teams", teams,
          source: Client::SOURCE, fetched_at: response.fetched_at, model: FantasyTeam)
        teams
      end

      # Maps a league payload to teams.
      #
      # @param payload [Hash] the parsed league JSON, with the +mTeam+ and +mRoster+ views
      # @return [Array<FantasyTeam>]
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      def parse(payload)
        changed!("a league should be a JSON object, got #{payload.class}") unless payload.is_a?(Hash)
        teams = payload.fetch("teams") { changed!("a league has no \"teams\"; keys are #{payload.keys.inspect}") }
        changed!("league \"teams\" should be an array, got #{teams.class}") unless teams.is_a?(Array)

        teams.map { |row| team(row) }
      end

      # @return [String]
      def inspect
        "#<#{self.class.name}>"
      end

      private

      def team(row)
        changed!("a team should be an object, got #{row.class}") unless row.is_a?(Hash)
        roster = row["roster"]
        entries = roster.is_a?(Hash) ? roster["entries"] : nil
        changed!("team #{row["id"].inspect} has no roster entries; is the mRoster view missing?") unless entries.is_a?(Array)

        FantasyTeam.new(id: row["id"], location: row["location"], nickname: row["nickname"],
          abbrev: row["abbrev"], owner_ids: row["owners"] || [],
          entries: entries.map { |item| roster_entry(item) })
      rescue ArgumentError => e
        changed!("team #{row["id"].inspect} doesn't fit the FantasyTeam model: #{e.message}")
      end

      def roster_entry(row)
        changed!("a roster entry should be an object, got #{row.class}") unless row.is_a?(Hash)
        pool = row["playerPoolEntry"]
        player = (pool.is_a?(Hash) && pool["player"].is_a?(Hash)) ? pool["player"] : {}
        player_id = row["playerId"] || player["id"]
        changed!("a roster entry has no player ID: #{row.keys.inspect}") if player_id.nil?

        pro_team_id = player["proTeamId"]
        RosterEntry.new(player_id: player_id, full_name: player["fullName"], lineup_slot_id: row["lineupSlotId"],
          default_position_id: player["defaultPositionId"], pro_team_id: pro_team_id,
          pro_team: pro_team_code(pro_team_id), injury_status: player["injuryStatus"],
          acquisition_type: row["acquisitionType"])
      end

      # ESPN's team ID mapped to the NHL tri-code; +0+ (a free agent) and unknown IDs give +nil+.
      def pro_team_code(id)
        return nil unless id.is_a?(Integer) && id.positive?

        SportsIngest::Teams.find_by_source_id(:espn, id)&.tri_code
      end

      def positive_integer(value, name)
        return value if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "#{name} must be a positive Integer, got #{value.inspect}"
      end

      def changed!(message)
        raise SourceChangedError.new(message, source: Client::SOURCE)
      end
    end
  end
end
