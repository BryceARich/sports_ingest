# frozen_string_literal: true

require "date"
require "time"

module SportsIngest
  module NHL
    # The league standings on one date, from the web API's +/standings/{date}+.
    #
    # +teams+ keeps the NHL's order: by league rank. Dates and times are rebuilt from Strings, so
    # a +from_h+ of parsed JSON gives back an equal model.
    #
    # @example
    #   standings = SportsIngest::NHL::Standings.fetch(date: "2026-11-22")
    #   standings.season                                # => 2026 (the 2026-27 season)
    #   standings.find("CAR").points                    # => 39
    #   standings.division("Metropolitan").map(&:tri_code).first(3) # => ["CAR", "NJD", "NYI"]
    #
    # @!attribute [r] date
    #   @return [Date] the date the standings are as of
    # @!attribute [r] season
    #   @return [Integer, nil] the year the season starts (ADR 0006), +2026+ for 2026-27; +nil+
    #     when the payload has no teams
    # @!attribute [r] updated_at
    #   @return [Time] when the NHL last updated them (UTC)
    # @!attribute [r] wild_card
    #   @return [Boolean] whether the playoff format uses wild cards (the NHL's +wildCardIndicator+)
    # @!attribute [r] teams
    #   @return [Array<Standing>] every team, by league rank
    Standings = Model.define(:date, :season, :updated_at, :wild_card, :teams)

    # Reopened so methods resolve inside the class.
    class Standings
      # A date the web API accepts: +YYYY-MM-DD+.
      DATE = /\A\d{4}-\d{2}-\d{2}\z/

      # @param date [Date, String] a Date or +"YYYY-MM-DD"+
      # @param updated_at [Time, String] a Time or an ISO 8601 String
      # @param teams [Array<Standing, Hash>]
      # @param fields [Hash{Symbol => Object}] +season+ and +wild_card+
      # @raise [ArgumentError] if +date+ or +updated_at+ can't be parsed
      def initialize(date:, updated_at:, teams:, **fields)
        super(date: self.class.coerce_date(date), updated_at: coerce_time(updated_at),
              teams: teams.map { |team| Standing.coerce(team) }, **fields)
      end

      # The standings as a hash, with +date+ and +updated_at+ as ISO 8601 Strings so the JSON
      # round-trips through {.from_h}.
      #
      # @return [Hash{Symbol => Object}]
      def to_h
        super.merge(date: date.iso8601, updated_at: updated_at.iso8601)
      end

      # One team's standing.
      #
      # @param tri_code [String] such as +"CAR"+; any code {Teams.find} resolves also works,
      #   such as +"T.B"+
      # @return [Standing, nil] +nil+ if no team matches
      def find(tri_code)
        code = Teams.find(tri_code)&.tri_code || tri_code.to_s.upcase
        teams.find { |team| team.tri_code == code }
      end

      # The teams in one division, best first.
      #
      # @param name [String] such as +"Metropolitan"+ (case-insensitive)
      # @return [Array<Standing>] empty if no team is in that division
      def division(name)
        teams.select { |team| team.division.casecmp?(name.to_s) }.sort_by(&:division_rank)
      end

      # The teams in one conference, best first.
      #
      # @param name [String] such as +"Eastern"+ (case-insensitive)
      # @return [Array<Standing>] empty if no team is in that conference
      def conference(name)
        teams.select { |team| team.conference.casecmp?(name.to_s) }.sort_by(&:conference_rank)
      end

      class << self
        # Fetches the standings as of a date.
        #
        # @param date [Date, String, nil] a Date or +"YYYY-MM-DD"+; +nil+ means today's (the
        #   API's +/standings/now+)
        # @param client [Client] the client to fetch through
        # @return [Standings]
        # @raise [ArgumentError] if +date+ isn't a Date or +YYYY-MM-DD+
        # @raise [SourceChangedError] if the payload isn't shaped as expected
        # @raise [NotFound, HTTPError, ParseError] as {Client#get_json} does
        def fetch(date: nil, client: Client.new)
          path = date.nil? ? "standings/now" : "standings/#{coerce_date(date).iso8601}"
          from_payload(client.get_json(path), date: date)
        end

        # Builds standings from a parsed +/standings/{date}+ payload.
        #
        # @param payload [Hash{String => Object}] the parsed JSON
        # @param date [Date, String, nil] the date asked for; used when the payload has no teams
        #   (off-season dates); otherwise the rows' +date+ wins
        # @return [Standings]
        # @raise [SourceChangedError] if the payload isn't shaped as expected
        def from_payload(payload, date: nil)
          rows = payload.is_a?(Hash) && payload["standings"]
          raise SourceChangedError.new("NHL standings payload has no standings list", source: :nhl) unless rows.is_a?(Array)

          updated_at = parse_time(payload["standingsDateTimeUtc"])
          first = rows.first || {}
          new(
            date: first["date"] || date || updated_at.to_date,
            season: first["seasonId"].nil? ? nil : season_from(first["seasonId"]),
            updated_at: updated_at,
            wild_card: payload["wildCardIndicator"] == true,
            teams: rows.map { |row| Standing.from_payload(row) }
          )
        end

        # @api private
        # @param value [Date, String]
        # @return [Date]
        # @raise [ArgumentError] if it isn't a Date or +YYYY-MM-DD+
        def coerce_date(value)
          return value if value.instance_of?(Date)
          raise ArgumentError, "date must be a Date or YYYY-MM-DD, got #{value.inspect}" unless value.is_a?(String) && DATE.match?(value)

          Date.iso8601(value)
        rescue Date::Error
          raise ArgumentError, "date must be a valid YYYY-MM-DD, got #{value.inspect}"
        end

        private

        def parse_time(value)
          Time.iso8601(value.to_s).getutc
        rescue ArgumentError
          raise SourceChangedError.new("NHL standings standingsDateTimeUtc isn't a time: #{value.inspect}", source: :nhl)
        end

        def season_from(season_id)
          match = /\A(\d{4})(\d{4})\z/.match(season_id.to_s)
          raise SourceChangedError.new("NHL standings seasonId isn't YYYYYYYY: #{season_id.inspect}", source: :nhl) unless match

          match[1].to_i
        end
      end

      private

      def coerce_time(value)
        return value.getutc if value.is_a?(Time)

        Time.iso8601(value.to_s).getutc
      rescue ArgumentError
        raise ArgumentError, "updated_at must be a Time or ISO 8601 String, got #{value.inspect}"
      end
    end
  end
end
