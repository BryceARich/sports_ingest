# frozen_string_literal: true

module SportsIngest
  # The gem's two cache tiers (ADR 0003 in +docs/adr/0003-two-cache-tiers.md+).
  #
  # - {Raw}: HTTP responses keyed by request, with a TTL per source, served stale when the network
  #   fails (M1-06, ADR 0009 in +docs/adr/0009-raw-cache-stores-and-stale-on-error.md+).
  # - {Processed}: model collections with their source, +fetched_at+ and schema version, which
  #   consumers read instead of re-importing (M1-07, ADR 0010 in
  #   +docs/adr/0010-processed-cache-entries.md+).
  #
  # Both keep JSON-ready Hashes in a store: {MemoryStore}, {DiskStore} or {NullStore} (off).
  #
  # @example
  #   client = SportsIngest::Cache::Raw.new(client: SportsIngest::HTTP::Client.new(source: :nhl))
  #   client.get("https://api-web.nhle.com/v1/standings/now").body
  module Cache
    # Store modes, as named by {Configuration#raw_cache} and {Configuration#processed_cache}.
    MODES = %i[disk memory off].freeze

    # Tier names; each tier gets its own directory under {Configuration#cache_dir}.
    TIERS = %i[raw processed].freeze

    @memory_stores = {}
    @mutex = Mutex.new

    # The store for a tier and mode, shared by every cache of that tier that doesn't get its own.
    #
    # @param mode [Symbol] +:disk+, +:memory+ or +:off+
    # @param tier [Symbol] +:raw+ or +:processed+
    # @param configuration [Configuration] settings to read +cache_dir+ from, for +:disk+
    # @return [DiskStore, MemoryStore, NullStore] a {DiskStore} under +<cache_dir>/<tier>+, one
    #   process-wide {MemoryStore} per tier, or a {NullStore}
    # @raise [ConfigurationError] for an unknown mode or tier
    def self.store_for(mode, tier:, configuration: SportsIngest.configuration)
      raise ConfigurationError, "unknown cache tier #{tier.inspect}; use one of #{TIERS.join(", ")}" unless TIERS.include?(tier)

      case mode
      when :disk then DiskStore.new(configuration.cache_dir.join(tier.to_s))
      when :memory then @mutex.synchronize { @memory_stores[tier] ||= MemoryStore.new }
      when :off then NullStore.new
      else raise ConfigurationError, "unknown #{tier} cache mode #{mode.inspect}; use one of #{MODES.join(", ")}"
      end
    end
  end
end
