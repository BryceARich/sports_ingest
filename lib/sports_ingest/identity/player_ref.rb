# frozen_string_literal: true

module SportsIngest
  # Player identity: canonical IDs, the name normalizer, and later the matcher and crosswalk (M3).
  module Identity
    # One player's identity: the canonical ID plus each source's own ID for that player
    # (ADR 0004, ADR 0026).
    #
    # The canonical ID is the authoritative source's ID for the sport (the NHL player ID for
    # hockey, the nflverse +gsis_id+ for football), kept as a String. That source's entry in
    # +source_ids+ is filled in from it, so +source_id(:nhl)+ always works for a hockey player.
    # Canonical IDs are unique within a sport only; use {#key} when sports are mixed.
    #
    # @example
    #   ref = SportsIngest::Identity::PlayerRef.new(sport: :hockey, canonical_id: 8478402,
    #     source_ids: {espn: 3895074})
    #   ref.canonical_id         # => "8478402"
    #   ref.source_id(:nhl)      # => "8478402"
    #   ref.key                  # => "hockey:8478402"
    #   ref.with_source_id(:evolving_hockey, "CONNOR.MCDAVID").source_id(:evolving_hockey)
    #   # => "CONNOR.MCDAVID"
    PlayerRef = Model.define(:sport, :canonical_id, :source_ids)

    # Reopened so constants and methods resolve inside the class (a +define+ block is lexically
    # in +Identity+).
    class PlayerRef
      # The source whose player ID is the canonical ID, per sport (ADR 0004).
      CANONICAL_SOURCES = {hockey: :nhl, football: :nflverse}.freeze

      # What a canonical ID looks like, per sport: NHL player IDs are digits (+8478402+);
      # nflverse +gsis_id+s are two digits, a dash and seven digits (+00-0033873+).
      ID_FORMATS = {hockey: /\A[1-9]\d*\z/, football: /\A\d{2}-\d{7}\z/}.freeze

      # Source names: lowercase snake_case, such as +:nhl+ or +:evolving_hockey+.
      SOURCE_NAME = /\A[a-z][a-z0-9_]*\z/

      # @!attribute [r] sport
      #   @return [Symbol] +:hockey+ or +:football+
      # @!attribute [r] canonical_id
      #   @return [String] the authoritative source's ID for this player
      # @!attribute [r] source_ids
      #   @return [Hash{Symbol => String}] each source's ID for this player, including the
      #     canonical source's

      # @param sport [Symbol, String] a key of {CANONICAL_SOURCES}
      # @param canonical_id [String, Integer] the canonical source's ID; must match the sport's
      #   {ID_FORMATS} entry once turned into a String
      # @param source_ids [Hash{Symbol, String => String, Integer}] other sources' IDs; keys are
      #   lowercase source names such as +:espn+
      # @raise [ArgumentError] if the sport is unknown, an ID is blank or malformed, a source
      #   name isn't lowercase snake_case, or +source_ids+ gives the canonical source a
      #   different ID
      def initialize(sport:, canonical_id:, source_ids: {})
        sport = self.class.coerce_sport(sport)
        canonical_id = self.class.coerce_id(canonical_id)
        unless ID_FORMATS.fetch(sport).match?(canonical_id)
          raise ArgumentError, "#{canonical_id.inspect} isn't a valid #{sport} canonical ID"
        end

        ids = self.class.coerce_source_ids(source_ids)
        canonical_source = CANONICAL_SOURCES.fetch(sport)
        if ids.key?(canonical_source) && ids[canonical_source] != canonical_id
          raise ArgumentError, "source_ids[:#{canonical_source}] is #{ids[canonical_source].inspect}, " \
            "but the canonical ID is #{canonical_id.inspect}"
        end

        ids = {canonical_source => canonical_id}.merge(ids).sort.to_h
        super(sport: sport, canonical_id: canonical_id, source_ids: ids)
      end

      # The source whose ID is canonical for this player's sport.
      #
      # @return [Symbol] for example +:nhl+
      def canonical_source
        CANONICAL_SOURCES.fetch(sport)
      end

      # This player's ID in one source.
      #
      # @param source [Symbol, String] a source name, such as +:espn+
      # @return [String, nil] the ID, or +nil+ if this ref has none for that source
      def source_id(source)
        source_ids[source.to_sym]
      end

      # A copy of this ref with one source's ID added or replaced.
      #
      # @param source [Symbol, String] a source name, such as +:espn+
      # @param id [String, Integer] that source's ID for this player
      # @return [PlayerRef] the new ref; this one is unchanged
      # @raise [ArgumentError] if the ID or source name is invalid, or +source+ is the canonical
      #   source with a different ID
      def with_source_id(source, id)
        with(source_ids: source_ids.merge(source.to_sym => id))
      end

      # A string that identifies this player across sports, for use as a map key.
      #
      # @return [String] +"<sport>:<canonical_id>"+, for example +"hockey:8478402"+
      def key
        "#{sport}:#{canonical_id}"
      end

      class << self
        # @api private
        # @param sport [Symbol, String]
        # @return [Symbol] the sport as a key of {CANONICAL_SOURCES}
        # @raise [ArgumentError] if the sport isn't supported
        def coerce_sport(sport)
          symbol = sport.to_s.to_sym
          return symbol if CANONICAL_SOURCES.key?(symbol)

          raise ArgumentError, "unknown sport #{sport.inspect}; expected one of " \
            "#{CANONICAL_SOURCES.keys.join(", ")}"
        end

        # @api private
        # @param id [String, Integer]
        # @return [String] the ID as a stripped String
        # @raise [ArgumentError] if the ID isn't a String or Integer, or is blank
        def coerce_id(id)
          unless id.is_a?(String) || id.is_a?(Integer)
            raise ArgumentError, "an ID must be a String or Integer, got #{id.class}"
          end

          string = id.to_s.strip
          raise ArgumentError, "an ID can't be blank" if string.empty?

          string
        end

        # @api private
        # @param source_ids [Hash{Symbol, String => String, Integer}]
        # @return [Hash{Symbol => String}]
        # @raise [ArgumentError] if it isn't a Hash, or a source name or ID is invalid
        def coerce_source_ids(source_ids)
          raise ArgumentError, "source_ids must be a Hash, got #{source_ids.class}" unless source_ids.is_a?(Hash)

          source_ids.to_h do |source, id|
            name = source.to_s
            raise ArgumentError, "invalid source name #{source.inspect}" unless SOURCE_NAME.match?(name)

            [name.to_sym, coerce_id(id)]
          end
        end
      end
    end
  end
end
