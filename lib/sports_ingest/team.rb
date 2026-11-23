# frozen_string_literal: true

module SportsIngest
  # One team: the NHL's ID and tri-code plus names, conference, division, colors, and each
  # source's own codes and IDs for it (ADR 0016). Look teams up through {Teams}.
  #
  # Like {Identity::PlayerRef}, IDs are Strings, and the canonical source's entries are filled
  # in from +id+ and +tri_code+, so +source_id(:nhl)+ and +codes_for(:nhl)+ always work.
  #
  # @example
  #   team = SportsIngest::Teams.fetch("T.B")
  #   team.tri_code              # => "TBL"
  #   team.division              # => "Atlantic"
  #   team.codes_for(:espn)      # => ["TB"]
  #   team.codes_for(:advanced_stats) # => ["T.B"]
  #   team.source_id(:espn)      # => "20"
  #   team.colors[:primary]      # => "#002868"
  Team = Model.define(:sport, :id, :tri_code, :name, :place_name, :common_name, :conference,
    :division, :colors, :source_ids, :codes)

  # Reopened so constants and methods resolve inside the class.
  class Team
    # The source whose IDs and codes are canonical, per sport.
    CANONICAL_SOURCES = {hockey: :nhl}.freeze

    # A color: +#+ and six uppercase hex digits.
    COLOR = /\A#[0-9A-F]{6}\z/

    # Fields that must be non-blank Strings.
    TEXT_FIELDS = %i[name place_name common_name conference division].freeze

    # @!attribute [r] sport
    #   @return [Symbol] +:hockey+
    # @!attribute [r] id
    #   @return [String] the canonical source's team ID, such as +"14"+
    # @!attribute [r] tri_code
    #   @return [String] the canonical source's code, such as +"TBL"+
    # @!attribute [r] name
    #   @return [String] the full name, such as +"Tampa Bay Lightning"+
    # @!attribute [r] place_name
    #   @return [String] such as +"Tampa Bay"+
    # @!attribute [r] common_name
    #   @return [String] such as +"Lightning"+
    # @!attribute [r] conference
    #   @return [String] such as +"Eastern"+
    # @!attribute [r] division
    #   @return [String] such as +"Atlantic"+
    # @!attribute [r] colors
    #   @return [Hash{Symbol => String}] +:primary+ and +:secondary+, as +"#RRGGBB"+
    # @!attribute [r] source_ids
    #   @return [Hash{Symbol => String}] each source's ID for this team, including the
    #     canonical source's
    # @!attribute [r] codes
    #   @return [Hash{Symbol => Array<String>}] each source's codes for this team, including
    #     the canonical source's tri-code

    # @param sport [Symbol, String] a key of {CANONICAL_SOURCES}
    # @param id [String, Integer] the canonical source's team ID
    # @param tri_code [String] the canonical source's code
    # @param colors [Hash{Symbol, String => String}] +primary+ and +secondary+ as +"#RRGGBB"+
    # @param source_ids [Hash{Symbol, String => String, Integer}] other sources' IDs
    # @param codes [Hash{Symbol, String => Array<String>}] other sources' codes
    # @param text [Hash{Symbol => String}] +name+, +place_name+, +common_name+, +conference+
    #   and +division+
    # @raise [ArgumentError] if the sport is unknown, a field is blank or the wrong type, a color
    #   isn't +#RRGGBB+, or a source name isn't lowercase snake_case
    def initialize(sport:, id:, tri_code:, colors:, source_ids: {}, codes: {}, **text)
      sport = Identity::PlayerRef.coerce_sport(sport)
      raise ArgumentError, "no teams for #{sport}" unless CANONICAL_SOURCES.key?(sport)

      canonical = CANONICAL_SOURCES.fetch(sport)
      id = Identity::PlayerRef.coerce_id(id)
      tri_code = self.class.coerce_text(:tri_code, tri_code)
      text = TEXT_FIELDS.to_h { |field| [field, self.class.coerce_text(field, text[field])] }
        .merge(text.except(*TEXT_FIELDS))
      ids = {canonical => id}.merge(Identity::PlayerRef.coerce_source_ids(source_ids)).sort.to_h
      codes = {canonical => [tri_code]}.merge(self.class.coerce_codes(codes)).sort.to_h

      super(sport: sport, id: id, tri_code: tri_code, colors: self.class.coerce_colors(colors),
            source_ids: ids, codes: codes, **text)
    end

    # This team's ID in one source.
    #
    # @param source [Symbol, String] a source name, such as +:espn+
    # @return [String, nil] the ID, or +nil+ if the table has none for that source
    def source_id(source)
      source_ids[source.to_sym]
    end

    # This team's codes in one source.
    #
    # @param source [Symbol, String] a source name, such as +:advanced_stats+
    # @return [Array<String>] the codes; empty if the table has none for that source
    def codes_for(source)
      codes.fetch(source.to_sym, [])
    end

    class << self
      # @api private
      # @param field [Symbol]
      # @param value [String]
      # @return [String] the value, stripped
      # @raise [ArgumentError] if it isn't a non-blank String
      def coerce_text(field, value)
        raise ArgumentError, "#{field} must be a String, got #{value.class}" unless value.is_a?(String)
        raise ArgumentError, "#{field} can't be blank" if value.strip.empty?

        value.strip
      end

      # @api private
      # @param colors [Hash{Symbol, String => String}]
      # @return [Hash{Symbol => String}] +:primary+ and +:secondary+, uppercased
      # @raise [ArgumentError] if either is missing or isn't +#RRGGBB+
      def coerce_colors(colors)
        raise ArgumentError, "colors must be a Hash, got #{colors.class}" unless colors.is_a?(Hash)

        colors = colors.transform_keys(&:to_sym)
        %i[primary secondary].to_h do |key|
          color = colors[key].to_s.upcase
          raise ArgumentError, "colors[:#{key}] must look like #RRGGBB, got #{colors[key].inspect}" unless COLOR.match?(color)

          [key, color]
        end
      end

      # @api private
      # @param codes [Hash{Symbol, String => Array<String>}]
      # @return [Hash{Symbol => Array<String>}]
      # @raise [ArgumentError] if a source name or code is invalid
      def coerce_codes(codes)
        raise ArgumentError, "codes must be a Hash, got #{codes.class}" unless codes.is_a?(Hash)

        codes.to_h do |source, list|
          name = source.to_s
          raise ArgumentError, "invalid source name #{source.inspect}" unless Identity::PlayerRef::SOURCE_NAME.match?(name)
          raise ArgumentError, "codes[:#{name}] must be an Array, got #{list.class}" unless list.is_a?(Array)

          [name.to_sym, list.map { |code| coerce_text(:code, code) }]
        end
      end
    end
  end
end
