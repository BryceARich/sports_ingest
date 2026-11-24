# frozen_string_literal: true

require "json"

module SportsIngest
  module Identity
    # Remembers what the matcher decided, so each source record is matched once (ADR 0031).
    #
    # {#resolve} checks, in order: a manual override (always, since overrides can change), then a
    # stored link from an earlier run, and only then {Matcher#match}. Matched results are stored;
    # unmatched results (+:ambiguous+, +:no_match+) are not, so they're retried when the known
    # players change. One file per sport, under +<cache_dir>/crosswalk/<sport>.json+ by default,
    # kept apart from the processed cache so +processed_cache = :off+ doesn't drop it.
    #
    # @example
    #   matcher = SportsIngest::Identity::Matcher.new(SportsIngest::NHL::Rosters.new.fetch("VAN"))
    #   crosswalk = SportsIngest::Identity::Crosswalk.new(matcher: matcher)
    #   match = crosswalk.resolve(source: :evolving_hockey, id: "ELIAS.PETTERSSON2", name: "Elias Pettersson", position: "D", team: "VAN")
    #   crosswalk.save
    class Crosswalk
      # Bumped when the file layout changes; a file with another version is ignored.
      FORMAT_VERSION = 1

      # @return [Matcher] the matcher that resolves records no stored link covers
      attr_reader :matcher

      # @param matcher [Matcher] the matcher for one sport; its {Matcher#sport} names the file
      # @param store [#read, #write, #delete, nil] where links live; +nil+ means a
      #   {Cache::DiskStore} under +<cache_dir>/crosswalk+
      # @param dir [String, Pathname, nil] the directory for the default store; +nil+ means
      #   +<cache_dir>/crosswalk+ from {SportsIngest.configuration}
      def initialize(matcher:, store: nil, dir: nil)
        @matcher = matcher
        @store = store || Cache::DiskStore.new(dir || SportsIngest.configuration.cache_dir.join("crosswalk"))
        @key = matcher.sport.to_s
        @links = load_links
        @dirty = false
      end

      # Resolves one source record, using a stored link when there is one.
      #
      # Takes the same arguments as {Matcher#match}. A matched result that isn't an override is
      # stored in memory; call {#save} to write it to disk.
      #
      # @param source [Symbol, String] the record's source, such as +:evolving_hockey+
      # @param name [String] the player's name as the source spells it
      # @param id [String, Integer, nil] the source's ID for the player, if it has one
      # @param birth_date [Date, String, nil] a Date or ISO 8601 date
      # @param position [String, nil] the position as the source spells it
      # @param team [String, nil] the team as the source spells it
      # @return [Match] the matched or unmatched result; a stored link reports its original reason
      #   with +detail+ prefixed by +crosswalk:+
      # @raise [ArgumentError] for the same bad input {Matcher#match} rejects
      def resolve(source:, name:, id: nil, birth_date: nil, position: nil, team: nil)
        override = matcher.override_for(source: source, name: name, id: id)
        return override if override

        key = link_key(source, name, id, birth_date, position, team)
        if (stored = stored_match(@links[key]))
          return stored
        end

        match = matcher.match(source: source, name: name, id: id, birth_date: birth_date, position: position, team: team)
        if match.matched? && match.reason != :override
          @links[key] = {"reason" => match.reason.to_s, "detail" => match.detail, "ref" => match.ref.to_h}
          @dirty = true
        end
        match
      end

      # Resolves many records and saves once at the end.
      #
      # @param records [Enumerable<Hash>] hashes of {#resolve} keyword arguments
      # @return [Array<Match>] one result per record, in order
      # @raise [Cache::Error] if the file can't be written
      def resolve_all(records)
        records.map { |record| resolve(**record) }.tap { save }
      end

      # Writes stored links to disk if any were added since the last save.
      #
      # @return [void]
      # @raise [Cache::Error] if the file can't be written
      def save
        return unless @dirty

        document = {"format_version" => FORMAT_VERSION, "sport" => @key, "links" => @links}
        @store.write(@key, JSON.parse(JSON.generate(document)))
        @dirty = false
      end

      # Forgets every stored link and deletes the file. Use after changing the matching rules.
      #
      # @return [void]
      def clear
        @links = {}
        @dirty = false
        @store.delete(@key)
      end

      # @return [Integer] how many stored links there are
      def size
        @links.size
      end

      private

      def load_links
        document = @store.read(@key)
        return {} unless document.is_a?(Hash) && document["format_version"] == FORMAT_VERSION
        return {} unless document["sport"] == @key && document["links"].is_a?(Hash)

        JSON.parse(JSON.generate(document["links"]))
      end

      def link_key(source, name, id, birth_date, position, team)
        JSON.generate([
          source.to_s,
          id.nil? ? nil : PlayerRef.coerce_id(id),
          name.to_s,
          birth_date&.to_s,
          position&.to_s,
          team&.to_s
        ])
      end

      # A stored link as a Match, or nil when it's missing or damaged (then the record is matched again).
      def stored_match(link)
        return nil unless link.is_a?(Hash)

        reason = link.fetch("reason").to_sym
        return nil unless Match::REASONS.key?(reason) && !%i[override ambiguous no_match].include?(reason)

        ref = PlayerRef.from_h(link.fetch("ref"))
        Match.new(ref: ref, reason: reason, detail: "crosswalk: #{link.fetch("detail")}")
      rescue KeyError, ArgumentError, TypeError, NoMethodError
        nil
      end
    end
  end
end
