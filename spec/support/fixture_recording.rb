# frozen_string_literal: true

require "uri"
require "vcr"

# Settings and scrubbing for the VCR cassettes under spec/fixtures/cassettes (ADR 0013).
#
# Specs replay cassettes and never reach the network. `rake fixtures:record` sets
# SPORTS_INGEST_RECORD to re-record them against the live sources.
module FixtureRecording
  # Where cassettes live, relative to the repo root.
  CASSETTE_DIR = File.expand_path("../fixtures/cassettes", __dir__)

  # Env var that turns recording on; its value is a VCR record mode.
  RECORD_ENV = "SPORTS_INGEST_RECORD"

  # Record modes the env var accepts. Unset means :none: replay only.
  RECORD_MODES = %i[none once new_episodes all].freeze

  # Headers dropped before a cassette is written: they carry credentials or tracking cookies.
  SCRUBBED_REQUEST_HEADERS = %w[Cookie Authorization].freeze
  SCRUBBED_RESPONSE_HEADERS = %w[Set-Cookie].freeze

  # Response headers that only add churn to diffs when a cassette is re-recorded.
  NOISY_RESPONSE_HEADERS = %w[Date Age Cf-Ray Cf-Cache-Status Report-To Nel Server-Timing X-Amz-Cf-Id X-Amz-Cf-Pop Via].freeze

  module_function

  # @param env [#[]] the environment
  # @return [Symbol] the VCR record mode
  # @raise [ArgumentError] for an unknown mode, or any mode but :none when CI is set
  def record_mode(env = ENV)
    value = env[RECORD_ENV].to_s.strip
    return :none if value.empty?

    mode = value.to_sym
    raise ArgumentError, "#{RECORD_ENV} must be one of #{RECORD_MODES.join(", ")}, got #{value.inspect}" unless RECORD_MODES.include?(mode)
    raise ArgumentError, "#{RECORD_ENV} is set in CI; CI only replays cassettes" if mode != :none && !env["CI"].to_s.empty?

    mode
  end

  # The secret values to replace, each with its placeholder. Covers the raw and URL-encoded forms,
  # since a SWID like "{ABC}" goes out as "%7BABC%7D" in a query string.
  #
  # @param configuration [SportsIngest::Configuration]
  # @return [Hash{String => String}] secret value to placeholder
  def secrets(configuration = SportsIngest.configuration)
    {"<ESPN_S2>" => configuration.espn_s2, "<ESPN_SWID>" => configuration.espn_swid}
      .each_with_object({}) do |(placeholder, secret), found|
        next if secret.nil?

        value = secret.reveal
        found[value] = placeholder
        found[URI.encode_www_form_component(value)] = placeholder
      end
  end

  # Removes credentials and noise from an interaction before VCR writes it.
  #
  # @param interaction [VCR::HTTPInteraction::HookAware]
  # @param secrets [Hash{String => String}] from {.secrets}
  # @return [void]
  def scrub(interaction, secrets = self.secrets)
    drop_headers(interaction.request.headers, SCRUBBED_REQUEST_HEADERS)
    drop_headers(interaction.response.headers, SCRUBBED_RESPONSE_HEADERS + NOISY_RESPONSE_HEADERS)
    secrets.each { |value, placeholder| interaction.filter!(value, placeholder) }
  end

  # Text in a cassette that means scrubbing missed something.
  #
  # @param text [String] a cassette's YAML
  # @return [Array<String>] what was found; empty when clean
  def leaks(text)
    headers = (SCRUBBED_REQUEST_HEADERS + SCRUBBED_RESPONSE_HEADERS).select do |name|
      text.match?(/^\s+#{Regexp.escape(name)}:\s*$/i)
    end
    headers + secrets.keys.select { |value| text.include?(value) }.map { "a configured ESPN cookie value" }.uniq
  end

  def drop_headers(headers, names)
    headers.delete_if { |name, _| names.any? { |drop| drop.casecmp?(name) } }
  end
end

VCR.configure do |config|
  config.cassette_library_dir = FixtureRecording::CASSETTE_DIR
  config.hook_into :webmock
  config.configure_rspec_metadata!
  # Specs without a cassette still use WebMock stubs; anything else fails instead of going out.
  config.allow_http_connections_when_no_cassette = false
  config.default_cassette_options = {
    record: FixtureRecording.record_mode,
    match_requests_on: %i[method uri],
    # The client asks for gzip and inflates bodies itself; store plain bodies so cassettes are
    # readable and secrets can be grepped for. Replay then serves them without Content-Encoding.
    decode_compressed_response: true,
    allow_unused_http_interactions: false
  }
  config.before_record { |interaction| FixtureRecording.scrub(interaction) }
end
