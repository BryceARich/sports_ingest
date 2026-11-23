# frozen_string_literal: true

require "json"

module SportsIngest
  module ESPN
    # Builds the JSON in ESPN's +X-Fantasy-Filter+ header, which narrows big responses such as the
    # player pool. Immutable: {#merge} returns a new filter.
    #
    # {.players} covers the common player-pool keys; anything else goes in through {.new} or
    # {#merge} as ESPN spells it.
    #
    # @example Top 50 free agents and waiver players by percent owned
    #   filter = SportsIngest::ESPN::Filter.players(limit: 50, status: [:free_agent, :waivers],
    #     sort_percent_owned: true)
    #   filter.to_header
    #   # => '{"players":{"limit":50,"filterStatus":{"value":["FREEAGENT","WAIVERS"]},' \
    #   #    '"sortPercOwned":{"sortPriority":1,"sortAsc":false}}}'
    class Filter
      # Player statuses accepted by {.players}, mapped to ESPN's values.
      STATUSES = {free_agent: "FREEAGENT", waivers: "WAIVERS", on_team: "ONTEAM"}.freeze

      # Builds a filter on the +players+ key. Every argument is optional; +nil+ leaves it out.
      #
      # @param limit [Integer, nil] at most this many players
      # @param offset [Integer, nil] skip this many first, for paging
      # @param ids [Array<Integer>, nil] only these ESPN player IDs (+filterIds+)
      # @param status [Array<Symbol>, Symbol, nil] keys of {STATUSES} (+filterStatus+)
      # @param slot_ids [Array<Integer>, nil] only players eligible for these lineup slots
      #   (+filterSlotIds+)
      # @param sort_percent_owned [Boolean] most-owned first (+sortPercOwned+)
      # @return [Filter]
      # @raise [ArgumentError] for an unknown status
      # @example
      #   SportsIngest::ESPN::Filter.players(ids: [4_024_854]).to_h
      #   # => {"players" => {"filterIds" => {"value" => [4024854]}}}
      def self.players(limit: nil, offset: nil, ids: nil, status: nil, slot_ids: nil, sort_percent_owned: false)
        players = {}
        players["limit"] = limit unless limit.nil?
        players["offset"] = offset unless offset.nil?
        players["filterIds"] = {"value" => Array(ids)} unless ids.nil?
        players["filterStatus"] = {"value" => Array(status).map { |s| status_value(s) }} unless status.nil?
        players["filterSlotIds"] = {"value" => Array(slot_ids)} unless slot_ids.nil?
        players["sortPercOwned"] = {"sortPriority" => 1, "sortAsc" => false} if sort_percent_owned
        new("players" => players)
      end

      # @param filter [Filter, Hash] a filter, or the Hash to build one from
      # @return [Filter]
      # @raise [ArgumentError] if +filter+ is neither
      def self.wrap(filter)
        case filter
        when Filter then filter
        when Hash then new(filter)
        else raise ArgumentError, "filter must be a #{name} or a Hash, got #{filter.class}"
        end
      end

      # @param hash [Hash] the filter as ESPN spells it; keys may be Symbols or Strings
      # @raise [ArgumentError] if +hash+ isn't a Hash
      # @example
      #   SportsIngest::ESPN::Filter.new(schedule: {filterMatchupPeriodIds: {value: [3]}})
      def initialize(hash = {})
        raise ArgumentError, "a filter must be a Hash, got #{hash.class}" unless hash.is_a?(Hash)

        @hash = deep_freeze(stringify(hash))
        freeze
      end

      # Deep-merges +other+ into this filter; +other+ wins on conflicts.
      #
      # @param other [Filter, Hash] what to add
      # @return [Filter] a new filter
      # @example
      #   Filter.players(limit: 50).merge(players: {offset: 50})
      def merge(other)
        Filter.new(deep_merge(@hash, Filter.wrap(other).to_h))
      end

      # @return [Hash{String => Object}] the filter, with String keys
      def to_h
        @hash
      end

      # @return [String] the JSON for the +X-Fantasy-Filter+ header
      def to_header
        JSON.generate(@hash)
      end

      # @param other [Object] the object to compare
      # @return [Boolean] whether +other+ is a {Filter} with the same content
      def ==(other)
        other.is_a?(Filter) && other.to_h == @hash
      end
      alias_method :eql?, :==

      # @return [Integer] a hash consistent with {#==}
      def hash
        [self.class, @hash].hash
      end

      # @return [String] the filter's JSON
      def inspect
        "#<#{self.class.name} #{to_header}>"
      end

      def self.status_value(status)
        STATUSES.fetch(status.to_s.downcase.to_sym) do
          raise ArgumentError, "status must be one of #{STATUSES.keys.join(", ")}, got #{status.inspect}"
        end
      end
      private_class_method :status_value

      private

      def stringify(value)
        case value
        when Hash then value.to_h { |key, inner| [key.to_s, stringify(inner)] }
        when Array then value.map { |inner| stringify(inner) }
        when String then value.dup
        else value
        end
      end

      def deep_freeze(value)
        case value
        when Hash then value.each_value { |inner| deep_freeze(inner) }
        when Array then value.each { |inner| deep_freeze(inner) }
        end
        value.freeze
      end

      def deep_merge(left, right)
        left.merge(right) do |_key, old, new|
          (old.is_a?(Hash) && new.is_a?(Hash)) ? deep_merge(old, new) : new
        end
      end
    end
  end
end
