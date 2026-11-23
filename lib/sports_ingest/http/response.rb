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
    Response = Data.define(:status, :headers, :body, :url) do
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
