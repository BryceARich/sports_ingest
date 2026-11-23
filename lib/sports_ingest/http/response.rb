# frozen_string_literal: true

module SportsIngest
  module HTTP
    # A successful response from {Client#get}, with the body already gunzipped.
    #
    # @!attribute [r] status
    #   @return [Integer] the HTTP status, 2xx
    # @!attribute [r] headers
    #   @return [Hash{String => String}] response headers, with lowercase names
    # @!attribute [r] body
    #   @return [String] the decoded body; UTF-8 for text and JSON unless the response names another
    #     charset, binary otherwise
    # @!attribute [r] url
    #   @return [String] the URL that answered, after any redirects
    # @!attribute [r] fetched_at
    #   @return [Time] when the response came from the network; older for one served from the raw
    #     cache ({Cache::Raw})
    # @!attribute [r] stale
    #   @return [Boolean] +true+ if {Cache::Raw} served this past its TTL because the network failed
    Response = Data.define(:status, :headers, :body, :url, :fetched_at, :stale) do
      # @param status [Integer] the HTTP status
      # @param headers [Hash{String => String}] response headers, with lowercase names
      # @param body [String] the decoded body
      # @param url [String] the URL that answered
      # @param fetched_at [Time] when it came from the network; now by default
      # @param stale [Boolean] whether it's a stale copy served on a network failure
      def initialize(status:, headers:, body:, url:, fetched_at: Time.now, stale: false)
        super
      end

      # @return [Boolean] whether this is a stale copy served because the network failed
      def stale? = stale

      # Looks up a header by name, ignoring case.
      #
      # @param name [String] the header name, e.g. "Content-Type"
      # @return [String, nil] the header value, or +nil+ if it's absent
      # @example
      #   response.header("Content-Type") # => "application/json; charset=utf-8"
      def header(name)
        headers[name.to_s.downcase]
      end
    end
  end
end
