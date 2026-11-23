# frozen_string_literal: true

require_relative "error"

module RepoTools
  # Builds the index table in docs/adr/README.md from the ADR files themselves (ADR 0072).
  #
  # The table is rewritten at release time, not in every PR, so parallel PRs that each add an ADR
  # don't conflict on it. Between releases {#problems} catches rows that are wrong, and
  # {#unindexed} lists ADRs that are still waiting for a row.
  class AdrIndex
    # An ADR file: a four-digit number (the issue number for new ADRs), a dash and a slug.
    FILE_NAME = /\A(\d{4})-[a-z0-9-]+\.md\z/

    TEMPLATE = "0000-template.md"
    HEADER = "| # | Decision | Status |"
    SEPARATOR = "|---|---|---|"

    # One ADR as the index shows it.
    Entry = Data.define(:number, :file, :title, :status) do
      # @return [String] the index table row for this ADR
      def row = "| [#{number}](#{file}) | #{title} | #{status} |"
    end

    # @param dir [String] the ADR directory, holding the ADR files and README.md
    def initialize(dir)
      @dir = dir
      @readme_path = File.join(dir, "README.md")
    end

    # @return [Array<Entry>] every ADR except the template, sorted by number, then file name
    # @raise [RepoTools::Error] if an ADR has no "# NNNN. Title" line matching its file name, or no Status line
    def entries
      files = Dir.children(@dir).grep(FILE_NAME).reject { |name| name == TEMPLATE }
      files.sort.map { |name| parse(name) }
    end

    # @return [String] the generated table, header included, ending in a newline
    def table
      [HEADER, SEPARATOR, *entries.map(&:row)].join("\n") + "\n"
    end

    # Replaces the table in README.md with {#table}.
    #
    # @return [Boolean] whether README.md changed
    # @raise [RepoTools::Error] if README.md has no index table
    def write!
      head, current, tail = split_readme
      return false if current == table

      File.write(@readme_path, "#{head}#{table}#{tail}")
      true
    end

    # Rows in README.md that don't match an ADR: a wrong title, status or link, a missing file,
    # a duplicate, or rows out of order.
    #
    # @return [Array<String>] one message per problem; empty when the table is correct
    # @raise [RepoTools::Error] if README.md has no index table or an ADR doesn't parse
    def problems
      expected = entries.to_h { |entry| [entry.file, entry.row] }
      rows = current_rows
      messages = rows.filter_map do |row|
        file = row[/\]\(([^)]+)\)/, 1]
        if file.nil? || !expected.key?(file)
          "row points at no ADR file: #{row}"
        elsif row != expected[file]
          "row for #{file} is out of date:\n  have: #{row}\n  want: #{expected[file]}"
        end
      end
      messages << "rows are duplicated or out of order; run `rake adr:index`" unless rows == rows.uniq.sort_by { |row| order(row) }
      messages
    end

    # @return [Array<Entry>] ADRs that have no row in README.md yet
    # @raise [RepoTools::Error] if README.md has no index table or an ADR doesn't parse
    def unindexed
      rows = current_rows
      entries.reject { |entry| rows.any? { |row| row.include?("](#{entry.file})") } }
    end

    private

    def parse(name)
      text = File.read(File.join(@dir, name), encoding: "UTF-8")
      number = name[FILE_NAME, 1]
      title = text[/\A# #{number}\. (.+)$/, 1]
      raise Error, "#{name}: first line must be \"# #{number}. Title\"" unless title

      status = text[/^- \*\*Status:\*\* (.+)$/, 1]
      raise Error, "#{name}: no \"- **Status:** ...\" line" unless status

      Entry.new(number: number, file: name, title: title.strip, status: status.strip)
    end

    def order(row)
      row[/\]\(([^)]+)\)/, 1].to_s
    end

    def current_rows
      split_readme[1].lines(chomp: true).drop(2)
    end

    # @return [Array(String, String, String)] README.md before the table, the table, and after it
    def split_readme
      readme = File.read(@readme_path, encoding: "UTF-8")
      start = readme.index(/^#{Regexp.escape(HEADER)}$/)
      raise Error, "#{@readme_path}: no index table starting with \"#{HEADER}\"" unless start

      lines = readme[start..].lines
      length = lines.take_while { |line| line.start_with?("|") }.sum(&:length)
      [readme[0...start], readme[start, length], readme[(start + length)..]]
    end
  end
end
