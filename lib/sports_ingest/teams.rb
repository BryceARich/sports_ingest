# frozen_string_literal: true

module SportsIngest
  # The team table, and lookups from any source's team code (ADR 0016).
  #
  # The table ships with the gem as Ruby data ({Teams::Hockey::ROWS}): the NHL's
  # team IDs, tri-codes, names, conferences and divisions, colors, plus the codes and IDs that
  # Evolving-Hockey, PuckPedia and ESPN use for each team. It lives in core so every source can
  # resolve teams without loading another source.
  #
  # Codes and names match loosely: case, accents, spaces and punctuation are ignored, so
  # +"T.B"+, +"tb"+ and +"TB"+ are the same code, and +"Montreal Canadiens"+ matches
  # +"Montréal Canadiens"+.
  #
  # @example
  #   SportsIngest::Teams.fetch("L.A").tri_code                  # => "LAK"
  #   SportsIngest::Teams.fetch("UTAH", source: :espn).name      # => "Utah Mammoth"
  #   SportsIngest::Teams.find("Tampa Bay Lightning").tri_code   # => "TBL"
  #   SportsIngest::Teams.find_by_source_id(:espn, 20).tri_code  # => "TBL"
  #   SportsIngest::Teams.find("XYZ")                            # => nil
  module Teams
    # Sports with a team table.
    SPORTS = %i[hockey].freeze

    class << self
      # Every team in a sport.
      #
      # @param sport [Symbol, String] one of {SPORTS}
      # @return [Array<Team>] sorted by tri-code, frozen
      # @raise [ArgumentError] if the sport has no table
      def all(sport: :hockey)
        table(sport)[:teams]
      end

      # The team a code or full name stands for.
      #
      # @param code [String, Symbol] a team code (+"TBL"+, +"T.B"+, +"TB"+) or full name
      # @param source [Symbol, String, nil] only match that source's codes, such as +:espn+;
      #   +nil+ matches any source's codes and the full name
      # @param sport [Symbol, String] one of {SPORTS}
      # @return [Team, nil] the team, or +nil+ if nothing matches
      # @raise [ArgumentError] if the sport has no table, or +source+ isn't in it
      def find(code, source: nil, sport: :hockey)
        index = table(sport)
        key = normalize(code)
        return index[:any][key] if source.nil?

        index[:by_source].fetch(source.to_sym) do
          raise ArgumentError, "no #{sport} team codes for source #{source.inspect}; " \
            "known: #{index[:by_source].keys.join(", ")}"
        end[key]
      end

      # Like {.find}, but raises when nothing matches.
      #
      # @param (see .find)
      # @return [Team]
      # @raise [NotFound] if no team matches +code+
      # @raise [ArgumentError] if the sport has no table, or +source+ isn't in it
      def fetch(code, source: nil, sport: :hockey)
        find(code, source: source, sport: sport) or
          raise NotFound, "no #{sport} team matches #{code.inspect}#{" in #{source}" if source}"
      end

      # The team with a given ID in one source.
      #
      # @param source [Symbol, String] a source name, such as +:nhl+ or +:espn+
      # @param id [String, Integer] that source's team ID
      # @param sport [Symbol, String] one of {SPORTS}
      # @return [Team, nil] the team, or +nil+ if no team has that ID
      # @raise [ArgumentError] if the sport has no table
      def find_by_source_id(source, id, sport: :hockey)
        table(sport)[:ids][[source.to_sym, id.to_s.strip]]
      end

      # The form codes and names are compared in: accents, case, spaces and punctuation removed.
      #
      # @param value [String, Symbol]
      # @return [String] for example +"tb"+ for +"T.B"+
      def normalize(value)
        value.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.gsub(/[^a-z0-9]/, "")
      end

      private

      def table(sport)
        sport = sport.to_s.to_sym
        raise ArgumentError, "no team table for #{sport.inspect}; known: #{SPORTS.join(", ")}" unless SPORTS.include?(sport)

        @tables ||= {}
        @tables[sport] ||= build(sport)
      end

      def build(sport)
        teams = const_get(sport.capitalize, false)::ROWS.map { |row| Team.from_h(row.merge(sport: sport)) }
        teams = teams.sort_by(&:tri_code).freeze

        any = {}
        by_source = {}
        ids = {}
        teams.each do |team|
          team.codes.each do |source, codes|
            codes.each do |code|
              add(by_source[source] ||= {}, normalize(code), team, "#{source} code #{code.inspect}")
              add(any, normalize(code), team, "code #{code.inspect}")
            end
          end
          add(any, normalize(team.name), team, "name #{team.name.inspect}")
          team.source_ids.each { |source, id| add(ids, [source, id], team, "#{source} ID #{id}") }
        end

        {teams: teams, any: any.freeze, by_source: by_source.freeze, ids: ids.freeze}.freeze
      end

      # A key two different teams share would make lookups depend on table order.
      def add(index, key, team, label)
        existing = index[key]
        if existing && existing != team
          raise Error, "team table: #{label} is used by both #{existing.tri_code} and #{team.tri_code}"
        end

        index[key] = team
      end
    end
  end
end
