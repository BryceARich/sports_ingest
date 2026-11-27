# frozen_string_literal: true

module SportsIngest
  module ESPN
    # One player on a fantasy team's roster, as ESPN's +mRoster+ view lists them.
    #
    # +player_id+ is ESPN's ID, not a canonical one: the crosswalk (M3) maps it to the NHL player
    # ID later (ADR 0037). +pro_team+ is the real team's tri-code, or +nil+ for a free agent or an
    # ESPN team ID the table doesn't know.
    #
    # @!attribute [r] player_id
    #   @return [Integer] ESPN's player ID
    # @!attribute [r] full_name
    #   @return [String, nil]
    # @!attribute [r] lineup_slot_id
    #   @return [Integer, nil] where the player sits: starter, bench, injured reserve, ...
    # @!attribute [r] default_position_id
    #   @return [Integer, nil] ESPN's position code; see the source note in +docs/sources/espn.md+
    # @!attribute [r] pro_team_id
    #   @return [Integer, nil] ESPN's real-team ID; +0+ for a free agent
    # @!attribute [r] pro_team
    #   @return [String, nil] the NHL tri-code, such as +"TBL"+
    # @!attribute [r] injury_status
    #   @return [String, nil] ESPN's injury label, such as +"ACTIVE"+ or +"DAY_TO_DAY"+
    # @!attribute [r] acquisition_type
    #   @return [String, nil] how the player joined the roster, such as +"DRAFT"+ or +"ADD"+
    #
    # @example
    #   team = SportsIngest::ESPN::Rosters.new(client: client).fetch(12_345, season: 2027).first
    #   team.entries.first.pro_team # => "TBL"
    RosterEntry = Model.define(:player_id, :full_name, :lineup_slot_id, :default_position_id,
      :pro_team_id, :pro_team, :injury_status, :acquisition_type)
  end
end
