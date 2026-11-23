# frozen_string_literal: true

# Flags files that look like Evolving-Hockey or PuckPedia exports, or data derived from them,
# so they never reach git (ADR 0005, ADR 0014). Used by script/licensed-data-guard, which the
# pre-commit hook and CI run. Plain stdlib, compatible with macOS system Ruby (2.6), because git
# hooks may run outside mise.
module LicensedDataGuard
  # Only data-like files are checked, so code and docs that name the sources stay allowed.
  DATA_EXTENSIONS = %w[
    .csv .tsv .txt .json .jsonl .ndjson .xls .xlsx .xlsm .ods .parquet .feather .rds
    .zip .gz .bz2 .xz .7z
  ].freeze

  # Data files whose name matches one of these look like an export.
  NAME_PATTERNS = {
    /(?:\A|[^a-z0-9])eh[_-]/i => "file name starts like an Evolving-Hockey export (EH_...)",
    /evolving[\s_-]*hockey/i => "file name mentions Evolving-Hockey",
    /puck[\s_-]*pedia/i => "file name mentions PuckPedia"
  }.freeze

  # Data files whose content matches one of these look like an export or a cache derived from one.
  CONTENT_PATTERNS = {
    /\bEH_ID\b/ => "contains an EH_ID column (Evolving-Hockey player ID)",
    /evolving[\s_-]*hockey/i => "mentions Evolving-Hockey",
    /puck[\s_-]*pedia/i => "mentions PuckPedia"
  }.freeze

  # Hand-made fixtures with the real column layouts and invented values live here.
  ALLOWED_PREFIXES = %w[spec/fixtures/advanced_hockey/].freeze

  # How much of each file's content is scanned.
  SCAN_BYTES = 256 * 1024

  module_function

  # Reasons a file looks like licensed data.
  #
  # @param path [String] path relative to the repo root
  # @param content [String, nil] the file's content, or nil to check the name only
  # @return [Array<String>] reasons, empty when the file looks fine
  def violations(path, content = nil)
    return [] if allowed?(path) || !data_file?(path)

    name = File.basename(path)
    reasons = NAME_PATTERNS.select { |re, _| name.match?(re) }.values
    if content
      text = content.byteslice(0, SCAN_BYTES).dup.force_encoding(Encoding::BINARY)
      reasons += CONTENT_PATTERNS.select { |re, _| text.match?(binary(re)) }.values
    end
    reasons.uniq
  end

  # @param path [String] path relative to the repo root
  # @return [Boolean] whether the path is in an allowed fixtures directory
  def allowed?(path)
    ALLOWED_PREFIXES.any? { |prefix| path.start_with?(prefix) }
  end

  # @param path [String] path relative to the repo root
  # @return [Boolean] whether the path has a data-like extension (e.g. +.csv+, +.csv.gz+)
  def data_file?(path)
    exts = File.basename(path).downcase.scan(/\.[a-z0-9]+/)
    exts.any? { |ext| DATA_EXTENSIONS.include?(ext) }
  end

  def binary(re)
    Regexp.new(re.source.b, re.options)
  end
  private_class_method :binary
end
