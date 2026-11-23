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
    end
  end
end
