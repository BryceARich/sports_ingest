# frozen_string_literal: true

require "date"

module SportsIngest
  module Identity
    # Resolves a source's player record to a canonical player. A manual override wins outright
    # (ADR 0029, +:override+). Otherwise, in tiers (ADR 0028):
    #
    # 1. the source's own ID, already on a known player's {PlayerRef} (+:exact+)
    # 2. name key ({NameNormalizer.key}) and birth date (+:high+)
    # 3. name key, position and team (+:medium+)
    # 4. a name key only one known player has (+:low+)
    #
    # The matcher is built from the known players of one sport, usually NHL rosters. Before
    # tiers 2 to 4, players whose birth date or position contradicts the record are set aside.
    # When a tier finds more than one player the record is +:ambiguous+ and later tiers aren't
    # tried; when nothing is left it's +:no_match+. Both come back with the players it could be.
    #
    # @example
    #   matcher = SportsIngest::Identity::Matcher.new(SportsIngest::NHL::Rosters.new.fetch("VAN"))
    #   match = matcher.match(source: :evolving_hockey, id: "ELIAS.PETTERSSON2", name: "Elias Pettersson",
    #     position: "D", team: "VAN")
    #   match.reason                          # => :name_position_team
    #   match.ref.source_id(:evolving_hockey) # => "ELIAS.PETTERSSON2"
    class Matcher
      # Hockey position spellings, mapped to the group they're compared in: +F+ (forward), +D+ or
      # +G+. Sources disagree about centre versus wing for the same forward, so those don't count.
      HOCKEY_POSITIONS = {
        "C" => "F", "L" => "F", "LW" => "F", "R" => "F", "RW" => "F", "W" => "F", "F" => "F",
        "D" => "D", "LD" => "D", "RD" => "D", "G" => "G"
      }.freeze

      # One known player, as the matcher indexes it.
      Known = Struct.new(:ref, :key, :birth_date, :position, :team)
      private_constant :Known

      # @return [Symbol] the sport of every known player
      attr_reader :sport

      # @param players [Enumerable<#ref, #full_name, #birth_date, #position, #team>] the known
      #   players, such as {NHL::Player}s; +birth_date+, +position+ and +team+ may be +nil+.
      #   A player listed twice (same canonical ID) is kept once.
      # @param overrides [Overrides] manual decisions, checked before any tier (ADR 0029); an
      #   override may name a player who isn't in +players+
      # @raise [ArgumentError] if there are no players, they're from more than one sport, two
      #   players share a source ID, or an override's canonical ID isn't valid for the sport
      def initialize(players, overrides: Overrides.new)
        pairs = players.map { |player| [coerce_ref(player), player] }.uniq { |ref, _| ref.key }
        raise ArgumentError, "a matcher needs at least one known player" if pairs.empty?

        sports = pairs.map { |ref, _| ref.sport }.uniq
        raise ArgumentError, "known players span sports: #{sports.join(", ")}" if sports.size > 1

        @sport = sports.first
        overrides.canonical_ids.each { |canonical_id| PlayerRef.new(sport: @sport, canonical_id: canonical_id) }
        @overrides = overrides
        @known = pairs.map { |ref, player| known(ref, player) }
        @by_key = @known.group_by(&:key)
        @by_canonical = @known.to_h { |entry| [entry.ref.canonical_id, entry] }
        @by_source_id = index_source_ids
      end

      # Matches one record from a source.
      #
      # @param source [Symbol, String] the record's source, such as +:evolving_hockey+
      # @param name [String] the player's name as the source spells it
      # @param id [String, Integer, nil] the source's ID for the player, if it has one
      # @param birth_date [Date, String, nil] a Date or ISO 8601 date
      # @param position [String, nil] such as +"C"+, +"LW"+, +"D"+ or +"F"+; hockey compares
      #   forward, defence or goalie only
      # @param team [String, nil] a team code or name in any source's spelling, such as +"T.B"+
      # @return [Match] the result; matched records carry +ref+ with +id+ added under +source+
      # @raise [ArgumentError] if +name+ has no letters, +birth_date+ isn't a date, or +id+ or
      #   +source+ is malformed
      def match(source:, name:, id: nil, birth_date: nil, position: nil, team: nil)
        source = source.to_sym
        id = PlayerRef.coerce_id(id) unless id.nil?
        if (override = @overrides.find(source: source, name: name, id: id))
          return overridden(*override, source, id)
        end

        by_id = id && @by_source_id[[source, id]]
        return found(by_id, :source_id, "#{source} ID #{id}", source, id) if by_id

        record = Known.new(nil, NameNormalizer.key(name), coerce_date(birth_date), position_code(position),
          team_code(team))
        if id && source == canonical_source
          return result(:no_match, "no known player has #{source} ID #{id}", @by_key.fetch(record.key, []))
        end

        match_by_name(record, source, id)
      end

      private

      def match_by_name(record, source, id)
        named = @by_key.fetch(record.key, [])
        return result(:no_match, "no known player named #{record.key.inspect}", []) if named.empty?

        consistent = named.reject { |entry| contradicts?(entry, record) }
        tiers(record).each do |reason, test, label|
          next unless test

          hits = consistent.select(&test)
          return found(hits.first, reason, label, source, id) if hits.size == 1
          return result(:ambiguous, "#{hits.size} players match #{label}", hits) if hits.size > 1
        end

        if consistent.empty?
          result(:no_match, "every #{record.key.inspect} contradicts the record's birth date or position", named)
        else
          result(:ambiguous, "#{consistent.size} players are named #{record.key.inspect}", consistent)
        end
      end

      # [reason, test (nil when the record lacks the fields), label] for tiers 2 to 4.
      def tiers(record)
        [
          [:name_and_birth_date, record.birth_date && ->(entry) { entry.birth_date == record.birth_date },
            "#{record.key.inspect} born #{record.birth_date}"],
          [:name_position_team, record.position && record.team && lambda { |entry|
            entry.team == record.team && entry.position && compatible?(entry.position, record.position)
          }, "#{record.key.inspect} (#{record.position}, #{record.team})"],
          [:unique_name, ->(_entry) { true }, "the only #{record.key.inspect}"]
        ]
      end

      def contradicts?(entry, record)
        return true if entry.birth_date && record.birth_date && entry.birth_date != record.birth_date

        !compatible?(entry.position, record.position)
      end

      # True when either side is unknown or both are in the same position group.
      def compatible?(left, right)
        left.nil? || right.nil? || left == right
      end

      # The player an override names: a known player when there is one, otherwise a ref built from
      # the canonical ID alone.
      def overridden(canonical_id, label, source, id)
        entry = @by_canonical[canonical_id]
        ref = entry ? entry.ref : PlayerRef.new(sport: @sport, canonical_id: canonical_id)
        ref = ref.with_source_id(source, id) if id && source != ref.canonical_source
        Match.new(ref: ref, reason: :override, detail: "override of #{label} to #{canonical_id}")
      end

      def found(entry, reason, label, source, id)
        ref = (id && source != entry.ref.canonical_source) ? entry.ref.with_source_id(source, id) : entry.ref
        Match.new(ref: ref, reason: reason, detail: "matched on #{label}")
      end

      def result(reason, detail, entries)
        Match.new(ref: nil, reason: reason, detail: detail, candidates: entries.map(&:ref))
      end

      def coerce_ref(player)
        PlayerRef.coerce(player.ref) or raise ArgumentError, "every known player needs a ref"
      end

      def known(ref, player)
        Known.new(ref, NameNormalizer.key(player.full_name), coerce_date(player.birth_date),
          position_code(player.position), team_code(player.team))
      end

      def index_source_ids
        @known.each_with_object({}) do |entry, index|
          entry.ref.source_ids.each do |source, id|
            other = index[[source, id]]
            if other
              raise ArgumentError, "#{source} ID #{id} is on both #{other.ref.key} and #{entry.ref.key}"
            end

            index[[source, id]] = entry
          end
        end
      end

      def canonical_source
        PlayerRef::CANONICAL_SOURCES.fetch(sport)
      end

      def coerce_date(value)
        case value
        when Date, nil then value
        when String then Date.iso8601(value)
        else raise ArgumentError, "birth_date must be a Date or ISO 8601 String, got #{value.class}"
        end
      rescue Date::Error
        raise ArgumentError, "birth_date #{value.inspect} isn't an ISO 8601 date"
      end

      def position_code(value)
        return nil if value.nil? || value.to_s.strip.empty?

        code = value.to_s.strip.upcase
        (@sport == :hockey) ? HOCKEY_POSITIONS.fetch(code, code) : code
      end

      def team_code(value)
        return nil if value.nil? || value.to_s.strip.empty?

        team = Teams.find(value, sport: @sport) if Teams::SPORTS.include?(@sport)
        team ? team.tri_code : Teams.normalize(value)
      end
    end
  end
end
