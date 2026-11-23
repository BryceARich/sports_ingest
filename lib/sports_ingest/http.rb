# frozen_string_literal: true

module SportsIngest
  # The shared HTTP client: the gem's only way out to the network (ADR 0008 in
  # +docs/adr/0008-http-client-on-net-http.md+).
  #
  # Adapters build a {Client} for their source and call {Client#get}. The client handles timeouts,
  # retries with exponential backoff on 429 and 5xx, per-host rate limits ({RateLimiter}), the
  # +User-Agent+ from {SportsIngest::Configuration#user_agent} and gzip, and raises only the gem's
  # own errors.
  #
  # @example
  #   client = SportsIngest::HTTP::Client.new(source: :nhl)
  #   client.get("https://api-web.nhle.com/v1/standings/now").body
  module HTTP
  end
end
