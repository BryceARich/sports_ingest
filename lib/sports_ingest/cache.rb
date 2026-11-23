# frozen_string_literal: true

module SportsIngest
  # The gem's two cache tiers (ADR 0003 in +docs/adr/0003-two-cache-tiers.md+).
  #
  # - {Raw}: HTTP responses keyed by request, with a TTL per source, served stale when the network
  #   fails (M1-06, ADR 0009 in +docs/adr/0009-raw-cache-stores-and-stale-on-error.md+).
  # - The processed tier (M1-07) stores normalized models.
  #
  # Both keep JSON-ready Hashes in a store: {MemoryStore}, {DiskStore} or {NullStore} (off).
  #
  # @example
  #   client = SportsIngest::Cache::Raw.new(client: SportsIngest::HTTP::Client.new(source: :nhl))
  #   client.get("https://api-web.nhle.com/v1/standings/now").body
  module Cache
    # Store modes, as named by {Configuration#raw_cache}.
    MODES = %i[disk memory off].freeze
  end
end
