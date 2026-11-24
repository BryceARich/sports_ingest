# frozen_string_literal: true

module SportsIngest
  module ESPN
    # A league's draft picks, order and keepers, read from the +mDraftDetail+ view.
    #
    # {#fetch} reads a season from the league itself; {#history} reads a past season through
    # +/leagueHistory/{leagueId}+, which ESPN keeps for every season a league has played. Both
    # return a {Draft}. See ADR 0036 (+docs/adr/0036-espn-draft-picks.md+).
    #
    # @example Last season's draft, as ESPN player IDs in pick order
    #   drafts = SportsIngest::ESPN::Drafts.new
    #   drafts.history(12_345, season: 2026).picks.map(&:player_id)
    class Drafts
      # The view that carries +draftDetail+ in a league payload.
      VIEW = "mDraftDetail"

      # @param client [Client] what fetches from ESPN; hockey by default
      def initialize(client: Client.new(game: :hockey))
        @client = client
      end

      # A draft for the league's current season, or any season the league itself serves.
      #
      # @param league_id [Integer] the ID in the league's URL
      # @param season [Integer] ESPN's season ID, as {Client#season} takes it
      # @return [Draft]
      # @raise [ArgumentError] if +league_id+ or +season+ isn't a positive Integer
      # @raise [AuthError] if the league is private and the cookies are missing or rejected
      # @raise [NotFound] if there's no such league or season
      # @raise [SourceChangedError] if the payload has no draft detail
      # @raise [HTTPError, ParseError] as {Client#get_json} does
      # @example
      #   SportsIngest::ESPN::Drafts.new.fetch(12_345, season: 2027).drafted
      def fetch(league_id, season:)
        payload = @client.league(league_id, season: season, views: [VIEW])
        parse(payload, season: season)
      end

      # A draft from a league's history, for a past season.
      #
      # @param league_id [Integer] the ID in the league's URL
      # @param season [Integer] the season to read, as {Client#season} takes it
      # @return [Draft]
      # @raise [ArgumentError] if +league_id+ or +season+ isn't a positive Integer
      # @raise [AuthError] if the league is private and the cookies are missing or rejected
      # @raise [NotFound] if the league has no entry for +season+
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      # @raise [HTTPError, ParseError] as {Client#get_json} does
      # @example
      #   SportsIngest::ESPN::Drafts.new.history(12_345, season: 2026).keepers.size
      def history(league_id, season:)
        payload = @client.get_json("leagueHistory/#{positive_integer(league_id, "league_id")}",
          views: [VIEW], params: {"seasonId" => positive_integer(season, "season")})
        changed!("leagueHistory should be a JSON array, got #{payload.class}") unless payload.is_a?(Array)
        entry = payload.find { |league| league.is_a?(Hash) && league["seasonId"] == season }
        raise NotFound.new("league #{league_id} has no history for season #{season}", source: :espn) unless entry

        parse(entry, season: season)
      end

      # Maps a league payload, with +mDraftDetail+, to a draft.
      #
      # @param payload [Hash] one league's parsed JSON
      # @param season [Integer] the season to record on the draft
      # @return [Draft]
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      def parse(payload, season:)
        changed!("a league should be a JSON object, got #{payload.class}") unless payload.is_a?(Hash)
        detail = payload.fetch("draftDetail") { changed!("the league has no draftDetail") }
        changed!("draftDetail should be a JSON object") unless detail.is_a?(Hash)
        picks = detail.fetch("picks") { changed!("draftDetail has no picks") }
        changed!("picks should be a JSON array") unless picks.is_a?(Array)

        Draft.new(season: season, drafted: detail["drafted"] == true, in_progress: detail["inProgress"] == true,
          picks: picks.map { |pick| pick_from(pick) }.sort_by(&:overall_pick))
      end

      private

      def pick_from(pick)
        changed!("a pick should be a JSON object") unless pick.is_a?(Hash)
        DraftPick.new(overall_pick: integer(pick, "overallPickNumber"), round: integer(pick, "roundId"),
          round_pick: integer(pick, "roundPickNumber"), team_id: integer(pick, "teamId"),
          player_id: integer(pick, "playerId"), keeper: pick["keeper"] == true)
      end

      def integer(hash, key)
        value = hash.fetch(key) { changed!("a pick has no #{key}") }
        changed!("#{key} should be an Integer, got #{value.inspect}") unless value.is_a?(Integer)

        value
      end

      def changed!(message)
        raise SourceChangedError.new("ESPN draft: #{message}", source: :espn)
      end

      def positive_integer(value, name)
        return value if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "#{name} must be a positive Integer, got #{value.inspect}"
      end
    end
  end
end
