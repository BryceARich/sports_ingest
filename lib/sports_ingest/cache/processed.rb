# frozen_string_literal: true

require "json"
require "time"

module SportsIngest
  module Cache
    # The processed cache tier: model collections saved as JSON with their metadata, so consumers
    # read normalized, matched results instead of re-importing (ADR 0010 in
    # +docs/adr/0010-processed-cache-entries.md+).
    #
    # - **Key:** chosen by the caller, in {DiskStore::KEY_FORMAT}, for example
    #   +"nhl/skaters/2025"+. Start it with the source so sources don't collide.
    # - **Collection:** an Array of instances of one model class ({Model.define}).
    # - **Metadata:** the source, +fetched_at+ (when the underlying data came from the source),
    #   the model class's +SCHEMA_VERSION+ and +written_at+.
    # - **Misses:** {#read} returns +nil+ when there's no entry, it was written for another model
    #   class or schema version, it's older than +max_age+, or it's damaged. Rebuild and
    #   {#write} again.
    # - **Round trip:** {#write} checks that the collection reads back +==+ to what was given and
    #   raises otherwise, so a model whose fields don't survive JSON fails loudly, not on read.
    #
    # @example
    #   cache = SportsIngest::Cache::Processed.new
    #   cache.write("nhl/teams/2025", teams, source: :nhl, fetched_at: response.fetched_at)
    #   entry = cache.read("nhl/teams/2025", model: Team)
    #   entry&.models     # => [#<data Team ...>, ...], or nil on a miss
    #   entry&.fetched_at # when the NHL data was fetched
    class Processed
      # Bumped when the stored entry layout changes; entries with another version read as misses.
      # Separate from each model's +SCHEMA_VERSION+, which covers the models' own fields.
      FORMAT_VERSION = 1

      # Source names: lowercase snake_case, such as +:nhl+ or +:evolving_hockey+.
      SOURCE_NAME = /\A[a-z][a-z0-9_]*\z/

      # One stored collection and its metadata, as {#read} and {#write} return it.
      #
      # @!attribute [r] models
      #   @return [Array<Model>] the collection, frozen
      # @!attribute [r] model
      #   @return [Class] the collection's model class
      # @!attribute [r] source
      #   @return [Symbol] the source the data came from, such as +:nhl+
      # @!attribute [r] schema_version
      #   @return [Integer] the model class's +SCHEMA_VERSION+ when the entry was written
      # @!attribute [r] fetched_at
      #   @return [Time] when the underlying data was fetched from the source (UTC)
      # @!attribute [r] written_at
      #   @return [Time] when the entry was written to the cache (UTC)
      Entry = Data.define(:models, :model, :source, :schema_version, :fetched_at, :written_at)

      # The store for a mode, shared by every {Processed} that doesn't get one of its own.
      #
      # @param mode [Symbol] +:disk+, +:memory+ or +:off+
      # @param configuration [Configuration] settings to read +cache_dir+ from, for +:disk+
      # @return [DiskStore, MemoryStore, NullStore] a {DiskStore} under +<cache_dir>/processed+,
      #   one process-wide {MemoryStore}, or a {NullStore}
      # @raise [ConfigurationError] for an unknown mode
      def self.store_for(mode, configuration = SportsIngest.configuration)
        Cache.store_for(mode, tier: :processed, configuration: configuration)
      end

      # @param store [DiskStore, MemoryStore, NullStore, nil] where entries live; +nil+ means
      #   {.store_for}({Configuration#processed_cache}) at each call
      # @param configuration [Configuration, nil] settings to read; +nil+ means
      #   {SportsIngest.configuration} at each call
      # @param clock [#call] returns the current Time; swap it in tests
      def initialize(store: nil, configuration: nil, clock: -> { Time.now })
        @store = store
        @configuration = configuration
        @clock = clock
      end

      # Saves a collection, replacing any entry under +key+.
      #
      # @param key [String] the entry's key, for example +"nhl/skaters/2025"+
      # @param models [Array<Model>] instances of +model+ (or of the first item's class); may be
      #   empty when +model+ is given
      # @param source [Symbol, String] the source the data came from, such as +:nhl+
      # @param fetched_at [Time, nil] when the underlying data was fetched, such as
      #   {HTTP::Response#fetched_at}; +nil+ means now
      # @param model [Class, nil] the model class; +nil+ means the first item's class
      # @return [Entry] what was written, as {#read} would return it
      # @raise [ConfigurationError] if +key+ isn't a safe relative path
      # @raise [ArgumentError] if +models+ isn't an Array of one named model class, +source+ isn't
      #   a lowercase snake_case name, or the collection doesn't read back unchanged from JSON
      # @raise [Error] if the disk store can't write
      def write(key, models, source:, fetched_at: nil, model: nil)
        check_key(key)
        model = check_models(models, model)
        now = @clock.call.utc
        entry = {
          "format_version" => FORMAT_VERSION,
          "source" => check_source(source).to_s,
          "model" => model.name,
          "schema_version" => model::SCHEMA_VERSION,
          "fetched_at" => (fetched_at || now).utc.iso8601(6),
          "written_at" => now.iso8601(6),
          "models" => models.map(&:to_h)
        }
        json = JSON.parse(JSON.generate(entry))
        written = round_trip(json, models, model)
        store.write(key, json)
        written
      rescue JSON::GeneratorError => e
        raise ArgumentError, "#{model.name} can't be written as JSON: #{e.message}"
      end

      # Reads a collection back.
      #
      # @param key [String] the entry's key
      # @param model [Class] the model class the entry must have been written for
      # @param max_age [Numeric, nil] seconds since +fetched_at+ after which the entry counts as a
      #   miss; +nil+ means any age
      # @return [Entry, nil] the entry, or +nil+ on a miss (see the class notes)
      # @raise [ConfigurationError] if +key+ isn't a safe relative path
      def read(key, model:, max_age: nil)
        check_key(key)
        entry = load(store.read(key), model)
        return nil if entry.nil?
        return nil if max_age && @clock.call - entry.fetched_at > max_age

        entry
      end

      # @param key [String] the entry's key
      # @return [void]
      # @raise [ConfigurationError] if +key+ isn't a safe relative path
      def delete(key)
        check_key(key)
        store.delete(key)
      end

      # @return [String] a summary that never includes cached contents
      def inspect
        "#<#{self.class.name} store=#{store.inspect}>"
      end

      private

      def configuration
        @configuration || SportsIngest.configuration
      end

      def store
        @store || self.class.store_for(configuration.processed_cache, configuration)
      end

      def check_key(key)
        raise ConfigurationError, "invalid cache key: #{key.inspect}" unless DiskStore::KEY_FORMAT.match?(key.to_s)
      end

      def check_source(source)
        name = source.to_s if source.is_a?(Symbol) || source.is_a?(String)
        raise ArgumentError, "source must be a lowercase snake_case name, got #{source.inspect}" unless SOURCE_NAME.match?(name.to_s)

        name.to_sym
      end

      def check_models(models, model)
        raise ArgumentError, "models must be an Array, got #{models.class}" unless models.is_a?(Array)

        model ||= models.first&.class
        unless model.is_a?(Class) && model < Model && model.const_defined?(:SCHEMA_VERSION)
          raise ArgumentError, "model must be a class from SportsIngest::Model.define, got #{model.inspect}"
        end
        raise ArgumentError, "#{model.inspect} has no name, so entries can't record it" if model.name.nil?

        stray = models.find { |item| !item.instance_of?(model) }
        raise ArgumentError, "every model must be a #{model.name}, got a #{stray.class}" unless stray.nil?

        model
      end

      def round_trip(json, models, model)
        written = begin
          build(json, model)
        rescue ArgumentError, TypeError, NoMethodError => e
          raise ArgumentError, "#{model.name} doesn't read back from JSON: #{e.message}"
        end
        index = models.each_index.find { |i| written.models[i] != models[i] }
        return written if index.nil?

        raise ArgumentError, "#{model.name} item #{index} doesn't read back unchanged from JSON; " \
          "coerce its non-JSON fields (symbols, times, nested models) in initialize"
      end

      def load(json, model)
        return nil unless json.is_a?(Hash) && json["format_version"] == FORMAT_VERSION
        return nil unless json["model"] == model.name && json["schema_version"] == model::SCHEMA_VERSION

        build(json, model)
      rescue ArgumentError, TypeError, NoMethodError, KeyError
        nil # a damaged entry reads as a miss
      end

      def build(json, model)
        Entry.new(
          models: json.fetch("models").map { |hash| model.from_h(hash) }.freeze,
          model: model,
          source: json.fetch("source").to_sym,
          schema_version: json.fetch("schema_version"),
          fetched_at: Time.iso8601(json.fetch("fetched_at")),
          written_at: Time.iso8601(json.fetch("written_at"))
        )
      end
    end
  end
end
