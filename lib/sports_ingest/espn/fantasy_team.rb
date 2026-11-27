# frozen_string_literal: true

module SportsIngest
  module ESPN
    # One team in a fantasy league, with its roster.
    #
    # @!attribute [r] id
    #   @return [Integer] the team's ID within its league
    # @!attribute [r] location
    #   @return [String, nil] the city part of the name, such as +"Tampa Bay"+
    # @!attribute [r] nickname
    #   @return [String, nil] the nickname part of the name, such as +"Rays"+
    # @!attribute [r] abbrev
    #   @return [String, nil] the team's short code in the league
    # @!attribute [r] owner_ids
    #   @return [Array<String>] ESPN owner GUIDs; empty when ESPN lists none
    # @!attribute [r] entries
    #   @return [Array<RosterEntry>] the roster, in ESPN's order
    #
    # @example
    #   team.name          # => "Tampa Bay Rays"
    #   team.entries.size # => 16
    FantasyTeam = Model.define(:id, :location, :nickname, :abbrev, :owner_ids, :entries) do
      # Builds a team, turning each roster entry hash into a {RosterEntry}.
      #
      # @param entries [Array<RosterEntry, Hash>] the roster
      # @param fields [Hash] the other attributes
      # @return [FantasyTeam]
      # @raise [ArgumentError] if +entries+ isn't an Array or a hash doesn't fit {RosterEntry}
      def initialize(entries:, **fields)
        raise ArgumentError, "entries must be an Array, got #{entries.class}" unless entries.is_a?(Array)

        super(entries: entries.map { |entry| RosterEntry.coerce(entry) }, **fields)
      end

      # The team's full name: location and nickname, joined; the parts that are present.
      #
      # @return [String] for example +"Tampa Bay Rays"+; empty when ESPN gave neither part
      def name
        [location, nickname].map { |part| part.to_s.strip }.reject(&:empty?).join(" ")
      end
    end
  end
end
