# frozen_string_literal: true

require "json"

module SportsIngest
  # Base for every model: an immutable value object built on Ruby's +Data+ (ADR 0011).
  #
  # Models compare by value, are deeply frozen, and round-trip through plain hashes and JSON.
  # Each model class carries a +SCHEMA_VERSION+; bump it whenever the fields or their meaning
  # change, so the processed cache can tell stale entries apart.
  #
  # @example Define a model, including one that coerces a nested model from a hash
  #   Team = SportsIngest::Model.define(:abbrev, :name)
  #   Player = SportsIngest::Model.define(:name, :team, schema_version: 2) do
  #     def initialize(team:, **fields)
  #       super(team: Team.coerce(team), **fields)
  #     end
  #   end
  #
  #   player = Player.new(name: "Connor McDavid", team: {abbrev: "EDM", name: "Edmonton"})
  #   Player.from_h(JSON.parse(player.to_json)) == player # => true
  #   Player::SCHEMA_VERSION                                # => 2
  module Model
    # Builds a model class: a +Data+ subclass with this module's serialization mixed in.
    #
    # @param fields [Array<Symbol>] the model's attribute names
    # @param schema_version [Integer] the class's +SCHEMA_VERSION+
    # @yield an optional block evaluated in the new class, as with +Data.define+
    # @return [Class] the new model class
    # @raise [ArgumentError] if +schema_version+ isn't a positive Integer
    def self.define(*fields, schema_version: 1, &block)
      unless schema_version.is_a?(Integer) && schema_version.positive?
        raise ArgumentError, "schema_version must be a positive Integer, got #{schema_version.inspect}"
      end

      klass = Data.define(*fields)
      klass.include(self)
      klass.extend(ClassMethods)
      klass.const_set(:SCHEMA_VERSION, schema_version)
      klass.class_eval(&block) if block
      klass
    end

    # Deep-freezes every field, copying unfrozen strings, arrays and hashes so callers'
    # objects are left alone.
    #
    # @param fields [Hash{Symbol => Object}] field values, as passed to +new+
    def initialize(**fields)
      super(**fields.transform_values { |value| Model.deep_freeze(value) })
    end

    # The model as a hash with symbol keys; nested models, arrays and hashes are converted too.
    #
    # @return [Hash{Symbol => Object}]
    def to_h
      super.transform_values { |value| Model.dump(value) }
    end

    # The model as JSON, from {#to_h}.
    #
    # @param args [Array] passed through to +JSON+'s generator
    # @return [String]
    def to_json(*args)
      to_h.to_json(*args)
    end

    # @api private
    # @param value [Object]
    # @return [Object] a frozen copy of +value+ (or +value+ itself when already frozen)
    def self.deep_freeze(value)
      case value
      when Array then value.map { |item| deep_freeze(item) }.freeze
      when Hash then value.to_h { |key, item| [deep_freeze(key), deep_freeze(item)] }.freeze
      when String then value.frozen? ? value : value.dup.freeze
      else value.freeze
      end
    end

    # @api private
    # @param value [Object]
    # @return [Object] +value+ with any models inside it turned into hashes
    def self.dump(value)
      case value
      when Model then value.to_h
      when Array then value.map { |item| dump(item) }
      when Hash then value.transform_values { |item| dump(item) }
      else value
      end
    end
  end
end
