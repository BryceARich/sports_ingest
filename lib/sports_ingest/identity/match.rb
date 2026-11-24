# frozen_string_literal: true

module SportsIngest
  module Identity
    # What {Matcher#match} decided for one source record (ADR 0028): the player it resolved to,
    # how sure it is, and why.
    #
    # @!attribute [r] ref
    #   @return [PlayerRef, nil] the matched player, with the source's ID added when one was
    #     given; +nil+ when unmatched
    # @!attribute [r] confidence
    #   @return [Symbol] one of {CONFIDENCES}, from +:exact+ (tier 1) down to +:none+ (unmatched)
    # @!attribute [r] reason
    #   @return [Symbol] one of {REASONS}: the tier that matched, or why nothing did
    # @!attribute [r] detail
    #   @return [String] the reason in words, for logs and the unmatched report
    # @!attribute [r] candidates
    #   @return [Array<PlayerRef>] for an unmatched record, the players it could be (same name
    #     key); empty when matched
    #
    # @example
    #   match = matcher.match(source: :evolving_hockey, name: "Elias Pettersson", position: "D", team: "VAN")
    #   match.matched?    # => true
    #   match.confidence  # => :medium
    #   match.reason      # => :name_position_team
    Match = Model.define(:ref, :confidence, :reason, :detail, :candidates)

    # Reopened so constants and methods resolve inside the class.
    class Match
      # Confidence levels, most to least sure.
      CONFIDENCES = %i[exact high medium low none].freeze

      # Reasons, with the confidence each one gives.
      REASONS = {
        source_id: :exact,
        name_and_birth_date: :high,
        name_position_team: :medium,
        unique_name: :low,
        ambiguous: :none,
        no_match: :none
      }.freeze

      # @param ref [PlayerRef, Hash, nil] the matched player; +nil+ exactly when the reason is
      #   +:ambiguous+ or +:no_match+
      # @param reason [Symbol, String] a key of {REASONS}
      # @param detail [String] the reason in words
      # @param candidates [Array<PlayerRef, Hash>] players the record could be, when unmatched
      # @param confidence [Symbol, String, nil] defaults to the reason's; when given it must agree
      # @raise [ArgumentError] if the reason is unknown, the confidence disagrees with it, or
      #   +ref+ is missing for a match (or present for a non-match)
      def initialize(ref:, reason:, detail:, candidates: [], confidence: nil)
        reason = reason.to_s.to_sym
        expected = REASONS.fetch(reason) do
          raise ArgumentError, "reason must be one of #{REASONS.keys.join(", ")}, got #{reason.inspect}"
        end
        if confidence && confidence.to_s.to_sym != expected
          raise ArgumentError, "confidence for #{reason} is #{expected}, got #{confidence.inspect}"
        end

        ref = PlayerRef.coerce(ref)
        if ref.nil? != (expected == :none)
          raise ArgumentError, (ref ? "an unmatched result can't have a ref" : "a match needs a ref")
        end

        super(ref: ref, confidence: expected, reason: reason, detail: detail.to_s,
              candidates: Array(candidates).map { |candidate| PlayerRef.coerce(candidate) })
      end

      # @return [Boolean] true when a player was found
      def matched?
        !ref.nil?
      end
    end
  end
end
