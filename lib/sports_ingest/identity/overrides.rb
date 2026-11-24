# frozen_string_literal: true

require "yaml"

module SportsIngest
  module Identity
    # Manual identity overrides (ADR 0029): (source, source ID or source name) to a canonical ID.
    # {Matcher#match} checks them before any tier, so a person's decision beats an automatic match.
    #
    # The YAML file is a list of entries, each with +source+, +canonical_id+ and exactly one of
    # +source_id+ or +source_name+:
    #
    #   - source: evolving_hockey
    #     source_id: ELIAS.PETTERSSON2
    #     canonical_id: 8483678
    #   - source: puckpedia
    #     source_name: Sebastian Aho
    #     canonical_id: 8478427
    #
    # Prefer +source_id+. A +source_name+ override applies to every record from that source with the
    # same name key ({NameNormalizer.key}), whatever its birth date, position or team.
    #
    # @example
    #   overrides = SportsIngest::Identity::Overrides.load("overrides.yml")
    #   overrides.find(source: :evolving_hockey, name: "Elias Pettersson", id: "ELIAS.PETTERSSON2")
    #   # => ["8483678", "evolving_hockey ID \"ELIAS.PETTERSSON2\""]
    class Overrides
      # The keys an entry may have.
      KEYS = %w[source source_id source_name canonical_id].freeze

      # Reads an overrides file.
      #
      # @param path [String, Pathname] a YAML file holding a list of entries; an empty file means
      #   no overrides
      # @return [Overrides]
      # @raise [ConfigurationError] if there is no file at +path+
      # @raise [ParseError] if the file isn't YAML, or isn't a list
      # @raise [ArgumentError] if an entry is malformed (see {#initialize})
      def self.load(path)
        raise ConfigurationError, "no overrides file at #{path}" unless File.file?(path)

        data = YAML.safe_load(File.read(path, encoding: "UTF-8"))
        raise ParseError, "#{path} must hold a list of overrides" unless data.nil? || data.is_a?(Array)

        new(data || [])
      rescue Psych::SyntaxError => e
        raise ParseError, "#{path} isn't valid YAML: #{e.message}"
      end

      # @param entries [Array<Hash>] entries as the file holds them; keys may be strings or symbols
      # @raise [ArgumentError] if an entry isn't a mapping, has an unknown key, lacks +source+ or
      #   +canonical_id+, gives both or neither of +source_id+ and +source_name+, or two entries
      #   give the same key different canonical IDs
      def initialize(entries = [])
        @by_id = {}
        @by_name = {}
        entries.each { |entry| add(entry) }
      end

      # The canonical IDs the overrides point at, for the matcher to check against its sport.
      #
      # @return [Array<String>] without duplicates
      def canonical_ids
        (@by_id.values + @by_name.values).uniq
      end

      # Finds the override for one source record. An ID override wins over a name override.
      #
      # @param source [Symbol, String] the record's source, such as +:evolving_hockey+
      # @param name [String] the player's name as the source spells it
      # @param id [String, Integer, nil] the source's ID for the player, if it has one
      # @return [Array(String, String), nil] the canonical ID and what matched, for the match's
      #   detail; +nil+ when no override applies
      # @raise [ArgumentError] if +name+ has no letters or +id+ is blank
      def find(source:, name:, id: nil)
        source = source.to_sym
        id = PlayerRef.coerce_id(id) unless id.nil?
        if id && (canonical_id = @by_id[[source, id]])
          return [canonical_id, "#{source} ID #{id.inspect}"]
        end

        key = NameNormalizer.key(name)
        canonical_id = @by_name[[source, key]]
        canonical_id && [canonical_id, "#{source} name #{key.inspect}"]
      end

      private

      def add(entry)
        raise ArgumentError, "an override must be a mapping, got #{entry.class}" unless entry.is_a?(Hash)

        fields = entry.transform_keys(&:to_s)
        unknown = fields.keys - KEYS
        raise ArgumentError, "unknown override keys: #{unknown.join(", ")}" unless unknown.empty?
        raise ArgumentError, "an override needs a source" unless fields.key?("source")
        raise ArgumentError, "an override needs a canonical_id" unless fields.key?("canonical_id")
        unless fields.key?("source_id") ^ fields.key?("source_name")
          raise ArgumentError, "an override needs exactly one of source_id or source_name"
        end

        source = fields["source"].to_s
        unless PlayerRef::SOURCE_NAME.match?(source)
          raise ArgumentError, "override source #{source.inspect} must be lowercase snake_case"
        end

        canonical_id = PlayerRef.coerce_id(fields["canonical_id"])
        if fields.key?("source_id")
          store(@by_id, [source.to_sym, PlayerRef.coerce_id(fields["source_id"])], canonical_id)
        else
          store(@by_name, [source.to_sym, NameNormalizer.key(fields["source_name"])], canonical_id)
        end
      end

      def store(index, key, canonical_id)
        existing = index[key]
        if existing && existing != canonical_id
          raise ArgumentError, "conflicting overrides for #{key.last.inspect}: #{existing} and #{canonical_id}"
        end

        index[key] = canonical_id
      end
    end
  end
end
