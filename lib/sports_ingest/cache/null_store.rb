# frozen_string_literal: true

module SportsIngest
  module Cache
    # Caching off: remembers nothing, so every read misses.
    #
    # @example
    #   SportsIngest::Cache::NullStore.new.read("nhl/abc") # => nil
    class NullStore
      # @param _key [String] ignored
      # @return [nil]
      def read(_key) = nil

      # @param _key [String] ignored
      # @param _entry [Hash] ignored
      # @return [void]
      def write(_key, _entry) = nil

      # @param _key [String] ignored
      # @return [void]
      def delete(_key) = nil

      # @return [Array<String>] always empty
      def keys = []

      # @return [void]
      def clear = nil
    end
  end
end
