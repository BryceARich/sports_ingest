# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

module SportsIngest
  module Nflverse
    # Downloads assets from +nflverse/nflverse-data+ GitHub releases to disk, once per upstream
    # update (ADR 0040 in +docs/adr/0040-nflverse-release-files-on-disk.md+).
    #
    # - **Freshness:** each tag's +timestamp.json+ (+last_updated+) is fetched through {Cache::Raw},
    #   so it's checked at most once per nflverse TTL ({Configuration#ttl_for}). A local copy whose
    #   recorded +last_updated+ matches is reused; otherwise the file is downloaded again.
    # - **Storage:** assets are plain files at +<dir>/<tag>/<file>+, with a +<file>.meta.json+
    #   beside each recording the URL, +last_updated+ and +fetched_at+. They don't go through
    #   {Cache::Raw}, which would hold large binary files as Base64 JSON. Writes are atomic.
    # - **Offline:** if the timestamp check or the download fails because of the network (no
    #   response, 408, 429 or 5xx), an existing local copy is returned with +stale: true+.
    #
    # @example
    #   downloader = SportsIngest::Nflverse::ReleaseDownloader.new
    #   release = downloader.fetch("stats_player", "stats_player_week_2025.csv")
    #   release.path         # => #<Pathname:~/.cache/sports_ingest/releases/nflverse/stats_player/...>
    #   release.last_updated # => "2026-11-22 05:12:43 EST"
    class ReleaseDownloader
      # Where release assets are downloaded from.
      BASE_URL = "https://github.com/nflverse/nflverse-data/releases/download"

      # The asset every tag carries, saying when its files last changed.
      TIMESTAMP_FILE = "timestamp.json"

      # Tags and asset names: plain file names, so a path built from them stays under {#dir}.
      NAME_FORMAT = /\A[A-Za-z0-9_-][\w.-]*\z/

      # Appended to an asset's path for the file recording where it came from and which upstream
      # update it matches.
      META_SUFFIX = ".meta.json"

      # Seconds to wait for each read; season files are several megabytes.
      READ_TIMEOUT = 60

      # Statuses that count as the network failing, so a local copy is served stale.
      STALE_STATUSES = [408, 429].freeze

      # @return [Pathname] the directory assets are kept under, one folder per tag
      attr_reader :dir

      # @param client [HTTP::Client, #get] makes the downloads; an nflverse {HTTP::Client} by default
      # @param timestamps [Cache::Raw, #get] fetches +timestamp.json+; a {Cache::Raw} around +client+
      #   by default
      # @param dir [String, Pathname, nil] where to keep assets; +<cache_dir>/releases/nflverse+ by
      #   default
      # @param configuration [Configuration, nil] settings to read; +nil+ means
      #   {SportsIngest.configuration}
      # @param clock [#call] returns the current Time; swap it in tests
      def initialize(client: nil, timestamps: nil, dir: nil, configuration: nil, clock: -> { Time.now })
        config = configuration || SportsIngest.configuration
        @client = client || HTTP::Client.new(source: :nflverse, read_timeout: READ_TIMEOUT, configuration: configuration)
        @timestamps = timestamps || Cache::Raw.new(client: @client, configuration: configuration)
        @dir = Pathname.new(File.expand_path((dir || config.cache_dir.join("releases", "nflverse")).to_s))
        @clock = clock
      end

      # Returns a local copy of a release asset, downloading it if there is none or upstream has
      # changed since.
      #
      # @param tag [String] the release tag, e.g. +"stats_player"+
      # @param file [String] the asset name, e.g. +"stats_player_week_2025.csv"+
      # @return [ReleaseFile] the local copy; +stale: true+ if the network failed and an older copy
      #   was returned instead
      # @raise [ArgumentError] if +tag+ or +file+ isn't a plain file name
      # @raise [NotFound] if the tag or asset doesn't exist
      # @raise [HTTPError] if the network fails and there's no local copy to fall back on
      # @raise [SourceChangedError] if +timestamp.json+ has no +last_updated+ string
      # @raise [ParseError] if +timestamp.json+ isn't JSON
      # @raise [Error] if the file can't be written
      # @example
      #   downloader.fetch("players", "players.csv").path.read
      def fetch(tag, file)
        path = path_for(tag, file)
        meta = read_meta(path)

        begin
          upstream, unchecked = last_updated(tag)
        rescue HTTPError => e
          raise unless meta && network_failure?(e)

          return release_file(path, tag, file, meta, stale: true)
        end
        return release_file(path, tag, file, meta, stale: unchecked) if meta && meta["last_updated"] == upstream

        download(path, tag, file, upstream, meta)
      end

      # The tag's +last_updated+ value from its +timestamp.json+, through the raw cache.
      #
      # @param tag [String] the release tag
      # @return [Array(String, Boolean)] the value, and whether the raw cache served it stale
      # @raise [ArgumentError] if +tag+ isn't a plain file name
      # @raise [NotFound, HTTPError] as {Cache::Raw#get} does
      # @raise [ParseError] if the body isn't JSON
      # @raise [SourceChangedError] if it has no +last_updated+ string
      def last_updated(tag)
        response = @timestamps.get(url_for(tag, TIMESTAMP_FILE))
        value = begin
          JSON.parse(response.body)
        rescue JSON::ParserError => e
          raise ParseError.new("#{tag}/#{TIMESTAMP_FILE} isn't JSON: #{e.message}", source: :nflverse)
        end
        stamp = value["last_updated"] if value.is_a?(Hash)
        unless stamp.is_a?(String) && !stamp.empty?
          raise SourceChangedError.new("#{tag}/#{TIMESTAMP_FILE} has no last_updated string", source: :nflverse)
        end

        [stamp, response.stale]
      end

      # @param tag [String] the release tag
      # @param file [String] the asset name
      # @return [String] the asset's download URL
      # @raise [ArgumentError] if +tag+ or +file+ isn't a plain file name
      def url_for(tag, file)
        check_names(tag, file)
        "#{BASE_URL}/#{tag}/#{file}"
      end

      # @return [String] a summary naming the directory
      def inspect
        "#<#{self.class.name} dir=#{dir}>"
      end

      private

      def check_names(*names)
        names.each do |name|
          next if name.is_a?(String) && NAME_FORMAT.match?(name) && !name.end_with?(META_SUFFIX)

          raise ArgumentError, "not a plain release tag or asset name: #{name.inspect}"
        end
      end

      def path_for(tag, file)
        check_names(tag, file)
        dir.join(tag, file)
      end

      def meta_path(path)
        Pathname.new("#{path}#{META_SUFFIX}")
      end

      def read_meta(path)
        return nil unless path.file?

        meta = JSON.parse(meta_path(path).read(encoding: Encoding::UTF_8))
        return nil unless meta.is_a?(Hash) && meta["last_updated"].is_a?(String)

        Time.iso8601(meta["fetched_at"].to_s)
        meta
      rescue Errno::ENOENT, Errno::EISDIR, JSON::ParserError, EncodingError, ArgumentError
        nil # a missing or damaged record means the copy can't be trusted, so it's downloaded again
      end

      def download(path, tag, file, upstream, meta)
        url = url_for(tag, file)
        begin
          response = @client.get(url)
        rescue HTTPError => e
          raise unless meta && network_failure?(e)

          return release_file(path, tag, file, meta, stale: true)
        end

        meta = {"url" => url, "last_updated" => upstream, "fetched_at" => @clock.call.utc.iso8601(6)}
        write_atomically(path, response.body.b)
        write_atomically(meta_path(path), JSON.generate(meta))
        release_file(path, tag, file, meta, stale: false)
      end

      def write_atomically(path, content)
        FileUtils.mkdir_p(path.dirname, mode: 0o700)
        tmp = path.dirname.join(".#{path.basename}.#{SecureRandom.hex(6)}.tmp")
        File.open(tmp, File::WRONLY | File::CREAT | File::EXCL | File::BINARY, 0o600) { |io| io.write(content) }
        File.rename(tmp, path)
      rescue SystemCallError, IOError => e
        FileUtils.rm_f(tmp) if tmp
        raise Error.new("can't write #{path}: #{e.message}", source: :nflverse)
      end

      def release_file(path, tag, file, meta, stale:)
        ReleaseFile.new(path: path, tag: tag, file: file, url: meta["url"] || url_for(tag, file),
          last_updated: meta["last_updated"], fetched_at: Time.iso8601(meta["fetched_at"]), stale: stale)
      end

      def network_failure?(error)
        error.status.nil? || error.status >= 500 || STALE_STATUSES.include?(error.status)
      end
    end
  end
end
