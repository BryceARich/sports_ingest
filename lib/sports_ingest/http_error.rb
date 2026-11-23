# frozen_string_literal: true

module SportsIngest
  # Raised when a request fails: a non-success status the more specific errors don't cover,
  # a timeout or a connection error.
  class HTTPError < Error
    # @return [Integer, nil] the response status, or +nil+ if no response arrived
    attr_reader :status

    # @return [String, nil] the requested URL
    attr_reader :url

    # @param message [String, nil] what went wrong; defaults to one built from +status+ and +url+
    # @param status [Integer, nil] the response status
    # @param url [String, nil] the requested URL (never one carrying secrets)
    # @param source [Symbol, nil] the source that failed
    def initialize(message = nil, status: nil, url: nil, source: nil)
      @status = status
      @url = url
      super(message || ["HTTP request failed", status && "with status #{status}", url && "for #{url}"].compact.join(" "),
        source: source)
    end
  end
end
