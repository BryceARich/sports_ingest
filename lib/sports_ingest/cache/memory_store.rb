# frozen_string_literal: true

require "json"

module SportsIngest
  module Cache
    # Keeps entries in a Hash for the life of the process. Thread-safe.
    #
    # @example
    #   store = SportsIngest::Cache::MemoryStore.new
    #   store.write("nhl/abc", {"status" => 200})
    #   store.read("nhl/abc") # => {"status" => 200}
    class MemoryStore
      def initialize
        @entries = {}
        @mutex = Mutex.new
      end

      # @param key [String] the entry's key
      # @return [Hash, nil] the entry, or +nil+ if there is none
      def read(key)
        @mutex.synchronize { @entries[key] }
      end

      # @param key [String] the entry's key
      # @param entry [Hash] a JSON-ready Hash. A frozen copy round-tripped through JSON is kept, so
      #   reads look the same as from a {DiskStore}.
      # @return [void]
      def write(key, entry)
        frozen = JSON.parse(JSON.generate(entry), freeze: true)
        @mutex.synchronize { @entries[key] = frozen }
      end

      # @param key [String] the entry's key
      # @return [void]
      def delete(key)
        @mutex.synchronize { @entries.delete(key) }
      end

      # Removes every entry.
      #
      # @return [void]
      def clear
        @mutex.synchronize { @entries.clear }
      end

      # @return [String] a summary that never includes entry contents
      def inspect
        "#<#{self.class.name} entries=#{@mutex.synchronize { @entries.size }}>"
      end
    end
  end
end
