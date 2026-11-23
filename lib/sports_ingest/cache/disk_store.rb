# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"

module SportsIngest
  module Cache
    # Keeps each entry as a JSON file under a directory: +<dir>/<key>.json+.
    #
    # Writes go to a temporary file that is then renamed into place, so readers never see half a
    # file. Files are created readable by the owner only (ESPN private-league data can end up here).
    # A file that can't be parsed reads as a miss.
    #
    # @example
    #   store = SportsIngest::Cache::DiskStore.new(SportsIngest.configuration.cache_dir.join("raw"))
    #   store.write("nhl/ab/abcdef", {"status" => 200})
    #   store.read("nhl/ab/abcdef") # => {"status" => 200}
    class DiskStore
      # Keys are relative paths made of these characters, so they can't leave {#dir}.
      KEY_FORMAT = %r{\A[\w-]+(/[\w-]+)*\z}

      # @return [Pathname] the directory entries live under
      attr_reader :dir

      # @param dir [String, Pathname] the directory to keep entries under; created on first write
      def initialize(dir)
        @dir = Pathname.new(File.expand_path(dir.to_s))
      end

      # @param key [String] the entry's key, e.g. +"nhl/ab/abcdef"+
      # @return [Hash, nil] the entry, or +nil+ if there is none or its file is unreadable
      # @raise [ConfigurationError] if +key+ isn't a safe relative path
      def read(key)
        JSON.parse(path_for(key).read)
      rescue Errno::ENOENT, Errno::EISDIR, JSON::ParserError, EncodingError
        nil
      end

      # @param key [String] the entry's key
      # @param entry [Hash] a JSON-ready Hash
      # @return [void]
      # @raise [ConfigurationError] if +key+ isn't a safe relative path
      # @raise [Error] if the file can't be written (a read-only or full disk, say)
      def write(key, entry)
        path = path_for(key)
        FileUtils.mkdir_p(path.dirname, mode: 0o700)
        tmp = path.sub_ext(".#{SecureRandom.hex(6)}.tmp")
        File.open(tmp, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(JSON.generate(entry)) }
        File.rename(tmp, path)
      rescue SystemCallError, IOError => e
        FileUtils.rm_f(tmp) if tmp
        raise Error, "can't write cache file #{path}: #{e.message}"
      end

      # @param key [String] the entry's key
      # @return [void]
      # @raise [ConfigurationError] if +key+ isn't a safe relative path
      def delete(key)
        FileUtils.rm_f(path_for(key))
      end

      # Every entry's key, found by listing the +.json+ files under {#dir}.
      #
      # @return [Array<String>] keys in no particular order; empty if {#dir} doesn't exist
      def keys
        Dir.glob("**/*.json", base: dir.to_s)
          .map { |path| path.delete_suffix(".json") }
          .select { |key| KEY_FORMAT.match?(key) }
      end

      # Removes every entry, by deleting {#dir}.
      #
      # @return [void]
      def clear
        FileUtils.rm_rf(dir)
      end

      # @return [String] a summary naming the directory
      def inspect
        "#<#{self.class.name} dir=#{dir}>"
      end

      private

      def path_for(key)
        raise ConfigurationError, "invalid cache key: #{key.inspect}" unless KEY_FORMAT.match?(key.to_s)

        dir.join("#{key}.json")
      end
    end
  end
end
