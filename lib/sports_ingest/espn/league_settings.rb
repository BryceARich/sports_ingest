# frozen_string_literal: true

module SportsIngest
  module ESPN
    # A league's settings, from the +mSettings+ and +mTeam+ views, as a plain Hash
    # (ADR 0033 in +docs/adr/0033-espn-league-settings-as-a-plain-hash.md+).
    #
    # Keys are Symbols; stat IDs are Integers ({StatIds}); slots are names ({LineupSlots}):
    #
    # - +:league_id+, +:season+, +:game+ (+"ffl"+ or +"fhl"+), +:name+, +:size+ (number of teams)
    # - +:scoring_type+: ESPN's value, such as +"H2H_POINTS"+ or +"H2H_CATEGORY"+
    # - +:scoring+: stat ID => points, for every scoring item (in a category league, the weight)
    # - +:scoring_by_slot+: slot => {stat ID => points} where a slot scores a stat differently.
    #   ESPN puts D/ST points-allowed and yards-allowed tiers here, with 0 in +:scoring+
    # - +:reverse_stat_ids+: stat IDs where lower is better, such as goals-against average
    # - +:roster_slots+: slot => count, for slots with a count above zero
    # - +:teams+: one Hash per team: +:id+, +:abbrev+, +:name+, +:owners+ (display names)
    #
    # Member IDs (ESPN's +SWID+ values, one of which is the configured cookie) are left out.
    # Nothing is written to the processed cache; the raw cache holds the response.
    #
    # @example A football league's scoring, with names
    #   settings = SportsIngest::ESPN::LeagueSettings.new(game: :football).fetch(12_345, season: 2026)
    #   settings[:scoring].to_h { |id, points| [SportsIngest::ESPN::StatIds.abbrev(:football, id), points] }
    #   # => {"PY" => 0.04, "PTD" => 4.0, "INT" => -2.0, ...}
    #   settings[:scoring_by_slot]["D/ST"][89] # => 5.0
    #   settings[:roster_slots]                # => {"QB" => 1, "RB" => 2, ..., "BE" => 7, "IR" => 1}
    class LeagueSettings
      # The views each request asks for.
      VIEWS = %w[mSettings mTeam].freeze

      # @return [Client] the client requests go through
      attr_reader :client

      # @param game [Symbol, String, nil] +:hockey+ or +:football+ (or ESPN's +fhl+ / +ffl+); used
      #   to build a {Client} when +client+ isn't given
      # @param client [Client, nil] what fetches from ESPN; its game wins over +game+
      # @raise [ArgumentError] if neither is given, or +game+ is unknown
      def initialize(game: nil, client: nil)
        raise ArgumentError, "give game: or client:" if game.nil? && client.nil?

        @client = client || Client.new(game: game)
      end

      # Fetches and parses a league's settings.
      #
      # @param league_id [Integer] the ID in the league's URL (+leagueId=+)
      # @param season [Integer] ESPN's season ID: the year a football season starts, the year a
      #   hockey season ends
      # @return [Hash{Symbol => Object}] the settings, as described on the class
      # @raise [AuthError] if the league is private and the cookies are missing or rejected
      # @raise [NotFound] if there's no such league
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      # @raise [ArgumentError, HTTPError, ParseError] as {Client#league} does
      def fetch(league_id, season:)
        parse(client.league(league_id, season: season, views: VIEWS))
      end

      # Maps an +mSettings+ + +mTeam+ payload to the settings Hash.
      #
      # @param payload [Hash] the parsed league JSON
      # @return [Hash{Symbol => Object}] the settings, as described on the class
      # @raise [SourceChangedError] if the payload isn't shaped as expected
      def parse(payload)
        changed!("a league should be a JSON object, got #{payload.class}") unless payload.is_a?(Hash)
        settings = object(payload, "settings", "the league")
        scoring = object(settings, "scoringSettings", "settings")
        items = array(scoring, "scoringItems", "scoringSettings")

        {
          league_id: payload["id"],
          season: payload["seasonId"],
          game: client.game,
          name: settings["name"],
          size: settings["size"],
          scoring_type: scoring["scoringType"],
          scoring: items.to_h { |item| [stat_id(item), number(item["points"], "points")] },
          scoring_by_slot: scoring_by_slot(items),
          reverse_stat_ids: items.select { |item| item["isReverseItem"] }.map { |item| stat_id(item) },
          roster_slots: roster_slots(object(settings, "rosterSettings", "settings")),
          teams: teams(payload)
        }
      end

      # @return [String]
      def inspect
        "#<#{self.class.name} game=#{client.game.inspect}>"
      end

      private

      def scoring_by_slot(items)
        items.each_with_object({}) do |item, by_slot|
          overrides = item["pointsOverrides"] || {}
          changed!("pointsOverrides should be an object, got #{overrides.class}") unless overrides.is_a?(Hash)

          overrides.each do |slot_id, points|
            (by_slot[slot_name(slot_id)] ||= {})[stat_id(item)] = number(points, "pointsOverrides")
          end
        end
      end

      def roster_slots(roster)
        counts = object(roster, "lineupSlotCounts", "rosterSettings")
        counts.each_with_object({}) do |(slot_id, count), slots|
          slots[slot_name(slot_id)] = count if count.is_a?(Integer) && count.positive?
        end
      end

      def teams(payload)
        owners = (payload["members"] || []).to_h { |member| [member["id"], member["displayName"]] }
        array(payload, "teams", "the league").map do |team|
          changed!("a team should be an object, got #{team.class}") unless team.is_a?(Hash)

          {
            id: team["id"],
            abbrev: team["abbrev"],
            name: team_name(team),
            owners: Array(team["owners"]).filter_map { |id| owners[id] }
          }
        end
      end

      # ESPN sends +name+; older seasons split it into +location+ and +nickname+.
      def team_name(team)
        return team["name"] if team["name"].is_a?(String) && !team["name"].strip.empty?

        [team["location"], team["nickname"]].compact.join(" ").strip
      end

      def stat_id(item)
        id = item.is_a?(Hash) ? item["statId"] : nil
        changed!("a scoring item should have an Integer statId, got #{item.inspect[0, 100]}") unless id.is_a?(Integer)

        id
      end

      def slot_name(slot_id)
        LineupSlots.name_for(client.game, slot_id)
      rescue ArgumentError
        changed!("a lineup slot ID should be an integer, got #{slot_id.inspect}")
      end

      def number(value, what)
        changed!("#{what} should be a number, got #{value.inspect}") unless value.is_a?(Numeric)

        value.to_f
      end

      def object(hash, key, where)
        value = hash[key]
        changed!("#{where} has no #{key.inspect} object (keys: #{hash.keys.first(10).inspect})") unless value.is_a?(Hash)

        value
      end

      def array(hash, key, where)
        value = hash[key]
        changed!("#{where} has no #{key.inspect} array (keys: #{hash.keys.first(10).inspect})") unless value.is_a?(Array)

        value
      end

      def changed!(message)
        raise SourceChangedError.new(message, source: Client::SOURCE)
      end
    end
  end
end
