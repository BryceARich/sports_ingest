# frozen_string_literal: true

# A stand-in for {SportsIngest::Nflverse::ReleaseDownloader} that writes the given bodies under a
# directory and returns a ReleaseFile for each, so specs don't touch the network.
class NflverseFakeDownloader
  # @return [Array<Array(String, String)>] each +[tag, file]+ asked for, in order
  attr_reader :requests

  # @param dir [Pathname] where bodies are written
  # @param files [Hash{String => String}] asset name to body, within any tag
  def initialize(dir, files)
    @dir = dir
    @files = files
    @requests = []
  end

  # @param tag [String]
  # @param file [String]
  # @return [SportsIngest::Nflverse::ReleaseFile]
  def fetch(tag, file)
    @requests << [tag, file]
    path = @dir.join(tag, file)
    path.dirname.mkpath
    path.write(@files.fetch(file))
    SportsIngest::Nflverse::ReleaseFile.new(path: path, tag: tag, file: file,
      url: "https://example.test/#{tag}/#{file}", last_updated: "2026-11-24 00:00:00 EST",
      fetched_at: Time.utc(2026, 11, 24), stale: false)
  end
end
