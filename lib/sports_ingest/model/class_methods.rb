# frozen_string_literal: true

module SportsIngest
  module Model
    # Class-level methods every model class gets from {Model.define}.
    module ClassMethods
      # Builds a model from a hash, such as {Model#to_h}'s output or parsed JSON.
      #
      # @param hash [Hash{Symbol, String => Object}] field values; keys may be symbols or strings
      # @return [Model] a new instance of this model class
      # @raise [ArgumentError] if a field is missing or the hash has a key the model doesn't define
      def from_h(hash)
        new(**hash.transform_keys(&:to_sym))
      end

      # Returns +value+ if it's already this model, or builds one from a hash. Use it in
      # +initialize+ to accept nested models either way.
      #
      # @param value [Model, Hash, nil]
      # @return [Model, nil] +nil+ only when +value+ is +nil+
      # @raise [ArgumentError] if +value+ is neither this model, a Hash nor +nil+
      def coerce(value)
        case value
        when self, nil then value
        when Hash then from_h(value)
        else raise ArgumentError, "can't build #{name || "model"} from #{value.class}"
        end
      end

      # @api private
      # Raises unless +value+ is an Integer (optionally at least +min+, optionally +nil+).
      #
      # @param name [Symbol] the field name, used in the message
      # @param value [Object]
      # @param min [Integer, nil] the smallest allowed Integer, or +nil+ for no bound
      # @param allow_nil [Boolean] whether +nil+ is allowed
      # @return [void]
      # @raise [ArgumentError] if the check fails
      def check_integer(name, value, min: nil, allow_nil: false)
        return if allow_nil && value.nil?
        return if value.is_a?(Integer) && (min.nil? || value >= min)

        expected = +"an Integer"
        expected << " of at least #{min}" if min
        expected << " or nil" if allow_nil
        raise ArgumentError, "#{name} must be #{expected}, got #{value.inspect}"
      end

      # @api private
      # Raises unless +value+ is +true+ or +false+ (or +nil+, when allowed).
      #
      # @param name [Symbol] the field name, used in the message
      # @param value [Object]
      # @param allow_nil [Boolean] whether +nil+ is allowed
      # @return [void]
      # @raise [ArgumentError] if the check fails
      def check_boolean(name, value, allow_nil: false)
        return if [true, false].include?(value) || (allow_nil && value.nil?)

        expected = allow_nil ? "true, false or nil" : "true or false"
        raise ArgumentError, "#{name} must be #{expected}, got #{value.inspect}"
      end

      # @api private
      # Raises unless +value+ is an Array of Strings.
      #
      # @param name [Symbol] the field name, used in the message
      # @param value [Object]
      # @return [Array<String>] +value+, unchanged
      # @raise [ArgumentError] if it isn't an Array of Strings
      def check_strings(name, value)
        return value if value.is_a?(Array) && value.all?(String)

        raise ArgumentError, "#{name} must be an Array of Strings, got #{value.inspect}"
      end

      # @api private
      # Coerces a raw-code hash: keys are checked and symbolized, values are converted by the block,
      # and the result is sorted by key.
      #
      # @param codes [Hash{Symbol, String => Object}] the raw codes, keyed by field or source name
      # @param keys [Array<Symbol>, Regexp] the allowed keys, or a pattern their names must match
      # @param noun [String] what a key is called in the error message, such as +"field"+
      # @yieldparam key [Symbol] one key
      # @yieldparam value [Object] that key's value; returns it coerced, or raises
      # @return [Hash{Symbol => Object}]
      # @raise [ArgumentError] if +codes+ isn't a Hash or a key isn't allowed
      def coerce_codes(codes, keys:, noun: "field", &block)
        raise ArgumentError, "codes must be a Hash, got #{codes.class}" unless codes.is_a?(Hash)

        codes.to_h do |key, value|
          symbol = key.to_s.to_sym
          allowed = keys.is_a?(Regexp) ? keys.match?(symbol.to_s) : keys.include?(symbol)
          raise ArgumentError, "codes has no #{noun} #{symbol.inspect}" unless allowed

          [symbol, block.call(symbol, value)]
        end.sort.to_h
      end
    end
  end
end
