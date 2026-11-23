# frozen_string_literal: true

require_relative "error"

module RepoTools
  # Folds changelog fragments (+changelog.d/<issue>.md+) into CHANGELOG.md at release time,
  # so parallel PRs never edit the same lines (ADR 0072).
  class Changelog
    # Keep a Changelog section types, in the order a release lists them.
    TYPES = %w[Added Changed Deprecated Removed Fixed Security].freeze

    # A fragment is named after its issue, optionally with a slug: +72.md+, +72-ci.md+.
    FRAGMENT_NAME = /\A(\d+)(?:-[a-z0-9-]+)?\.md\z/

    # Files in the fragments directory that are not fragments.
    IGNORED = %w[README.md].freeze

    UNRELEASED = "## [Unreleased]"

    # Parses Keep a Changelog sections: +### Type+ headings followed by +- entry+ bullets, where an
    # entry may wrap onto indented lines.
    #
    # @param text [String] the markdown to parse
    # @param name [String] what to call the text in error messages
    # @return [Hash{String => Array<String>}] entries by type, in the order they appear
    # @raise [RepoTools::Error] on an unknown type, an entry outside a section, or any other line
    def self.parse(text, name)
      sections = {}
      type = nil
      text.each_line(chomp: true).with_index(1) do |line, number|
        if (heading = line[/\A###\s+(.+?)\s*\z/, 1])
          raise Error, "#{name}:#{number}: unknown section \"#{heading}\" (use #{TYPES.join(", ")})" unless TYPES.include?(heading)
          type = heading
          sections[type] ||= []
        elsif line.start_with?("- ")
          raise Error, "#{name}:#{number}: entry before any ### section" unless type
          sections[type] << +line
        elsif line.strip.empty?
          next
        elsif line.start_with?(" ") && type && sections[type].any?
          sections[type].last << "\n" << line
        else
          raise Error, "#{name}:#{number}: expected a ### section or a - entry, got #{line.inspect}"
        end
      end
      sections.reject { |_type, entries| entries.empty? }
    end

    # @param changelog_path [String] path to CHANGELOG.md
    # @param fragments_dir [String] path to the changelog.d directory
    def initialize(changelog_path:, fragments_dir:)
      @changelog_path = changelog_path
      @fragments_dir = fragments_dir
    end

    # @return [Array<String>] fragment paths, highest issue number first
    # @raise [RepoTools::Error] if the directory holds a file that isn't named like a fragment
    def fragment_paths
      return [] unless Dir.exist?(@fragments_dir)

      names = Dir.children(@fragments_dir).reject { |name| name.start_with?(".") || IGNORED.include?(name) }
      misnamed = names.grep_v(FRAGMENT_NAME)
      raise Error, "#{@fragments_dir}: not named <issue>.md or <issue>-<slug>.md: #{misnamed.join(", ")}" if misnamed.any?

      names.sort_by { |name| [-name[FRAGMENT_NAME, 1].to_i, name] }.map { |name| File.join(@fragments_dir, name) }
    end

    # Parses every fragment and the entries still listed under "Unreleased" in CHANGELOG.md.
    #
    # @return [Hash{String => Array<String>}] the merged entries by type, fragments first
    # @raise [RepoTools::Error] if any fragment or the Unreleased section doesn't parse
    def entries
      parsed = fragment_paths.map { |path| self.class.parse(File.read(path, encoding: "UTF-8"), path) }
      parsed << self.class.parse(unreleased_body, "#{@changelog_path} (Unreleased)")
      TYPES.to_h { |type| [type, parsed.flat_map { |sections| sections.fetch(type, []) }] }
        .reject { |_type, list| list.empty? }
    end

    # @param version [String] the version being released, e.g. "0.2.0"
    # @param date [String] the release date, YYYY-MM-DD
    # @return [String] the release section built from {#entries}
    # @raise [RepoTools::Error] if there is nothing to release
    def section(version:, date:)
      merged = entries
      raise Error, "nothing to release: no fragments and no entries under Unreleased" if merged.empty?

      body = merged.map { |type, list| "### #{type}\n\n#{list.join("\n")}\n" }
      "## [#{version}] - #{date}\n\n#{body.join("\n")}"
    end

    # Writes the release section into CHANGELOG.md below an empty "Unreleased" heading, then
    # deletes the fragments it used.
    #
    # @param version [String] the version being released
    # @param date [String] the release date, YYYY-MM-DD
    # @return [Array<String>] the fragment paths that were deleted
    # @raise [RepoTools::Error] if the version is already in CHANGELOG.md or nothing is unreleased
    def compile!(version:, date:)
      raise Error, "#{@changelog_path} already has a [#{version}] section" if changelog.include?("## [#{version}]")

      release = section(version: version, date: date)
      head, _body, tail = split
      File.write(@changelog_path, "#{head}#{UNRELEASED}\n\n#{release}\n#{tail}")
      fragment_paths.each { |path| File.delete(path) }
    end

    private

    def changelog
      @changelog ||= File.read(@changelog_path, encoding: "UTF-8")
    end

    def unreleased_body
      split[1]
    end

    # @return [Array(String, String, String)] text before the Unreleased heading, its body, and the rest
    def split
      start = changelog.index(/^#{Regexp.escape(UNRELEASED)}\s*$/)
      raise Error, "#{@changelog_path}: no \"#{UNRELEASED}\" heading" unless start

      body_start = changelog.index("\n", start)&.+(1) || changelog.length
      body_end = changelog.index(/^## \[/, body_start) || changelog.length
      [changelog[0...start], changelog[body_start...body_end], changelog[body_end..]]
    end
  end
end
