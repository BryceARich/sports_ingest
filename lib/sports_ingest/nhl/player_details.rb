# frozen_string_literal: true

module SportsIngest
  module NHL
    # Everything +/player/{id}/landing+ says about one player: the same {Player} a roster gives
    # (bio, position, current team), plus draft, career totals and season-by-season totals
    # (ADR 0023).
    #
    # +player.team+ is the player's current team, +nil+ when they have none (retired, unsigned).
    #
    # @!attribute [r] player
    #   @return [Player] identity, position and bio
    # @!attribute [r] active
    #   @return [Boolean] whether the NHL lists the player as active
    # @!attribute [r] draft
    #   @return [Draft, nil] +nil+ for an undrafted player
    # @!attribute [r] career_regular_season
    #   @return [StatLine, nil] NHL regular-season career totals; +nil+ before an NHL game
    # @!attribute [r] career_playoffs
    #   @return [StatLine, nil] NHL playoff career totals; +nil+ before a playoff game
    # @!attribute [r] seasons
    #   @return [Array<StatLine>] one line per season, game type and team, every league the NHL
    #     lists (junior and international included), oldest first
    #
    # @example
    #   mcdavid = SportsIngest::NHL::Players.new.fetch(8478402)
    #   mcdavid.player.birth_date                 # => #<Date: 1997-01-13>
    #   mcdavid.player.shoots_catches             # => "L"
    #   mcdavid.career_regular_season.points      # => 1278
    #   mcdavid.nhl_seasons(game_type: :playoffs).map(&:season)
    PlayerDetails = Model.define(:player, :active, :draft, :career_regular_season, :career_playoffs, :seasons)

    # Reopened so methods resolve inside the class.
    class PlayerDetails
      # @param player [Player, Hash]
      # @param active [Boolean]
      # @param draft [Draft, Hash, nil]
      # @param career_regular_season [StatLine, Hash, nil]
      # @param career_playoffs [StatLine, Hash, nil]
      # @param seasons [Array<StatLine, Hash>]
      # @raise [ArgumentError] if +active+ isn't a Boolean, +seasons+ isn't an Array, or a nested
      #   model rejects its fields
      def initialize(player:, active:, seasons:, draft: nil, career_regular_season: nil, career_playoffs: nil)
        raise ArgumentError, "active must be true or false, got #{active.inspect}" unless [true, false].include?(active)
        raise ArgumentError, "seasons must be an Array, got #{seasons.class}" unless seasons.is_a?(Array)

        super(player: Player.coerce(player), active: active, draft: Draft.coerce(draft),
              career_regular_season: StatLine.coerce(career_regular_season),
              career_playoffs: StatLine.coerce(career_playoffs), seasons: seasons.map { StatLine.coerce(it) })
      end

      # @return [Boolean] whether the NHL lists the player as active
      def active?
        active
      end

      # @return [String] the NHL player ID
      def id
        player.id
      end

      # @return [String] such as +"Connor McDavid"+
      def full_name
        player.full_name
      end

      # The player's NHL lines, one per season and team (a traded player has two in that season).
      #
      # @param game_type [Symbol] +:regular+ or +:playoffs+
      # @return [Array<StatLine>] oldest first
      def nhl_seasons(game_type: :regular)
        seasons.select { |line| line.league == "NHL" && line.game_type == game_type }
      end
    end
  end
end
