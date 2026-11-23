# frozen_string_literal: true

module SportsIngest
  module AdvancedHockey
    module PuckPedia
      module CapHit2026
        # One export row turned into a {Contract}, with each value checked.
        # @api private
        class Row
          # @param values [Hash{Symbol => String, nil}] stripped cells by field, blank as +nil+
          # @param where [String] file and line, for error messages
          def initialize(values, where)
            @values = values
            @where = where
          end

          # @return [Contract]
          # @raise [SourceChangedError] if a value doesn't fit the format
          def contract
            last_name, first_name = name_parts
            contract_year, status_length = status
            start_season = season(:start_season)
            expiry_season = season(:expiry_season)
            length = whole(:length)

            unless status_length == length && expiry_season - start_season + 1 == length
              invalid("Status #{raw(:status)}, Length #{raw(:length)} and seasons " \
                      "#{raw(:start_season)} to #{raw(:expiry_season)} disagree")
            end

            Contract.new(
              name: "#{first_name} #{last_name}", first_name:, last_name:,
              age: whole(:age), position:, cap_hit: dollars, contract_year:, length:,
              start_season:, expiry_season:, expiry_status: required(:expiry_status),
              agent: @values[:agent], signing_gm: @values[:signing_gm]
            )
          end

          private

          def name_parts
            parts = required(:player).split(",").map(&:strip)
            invalid("Player #{raw(:player).inspect} isn't \"Last, First\"") unless parts.size == 2 && parts.none?(&:empty?)
            parts
          end

          def status
            match = /\AYR (\d+) OF (\d+)\z/i.match(required(:status))
            invalid("Status #{raw(:status).inspect} isn't \"YR n OF m\"") unless match && match[1].to_i <= match[2].to_i
            [match[1].to_i, match[2].to_i]
          end

          def season(field)
            match = /\A(\d{4})-(\d{2})\z/.match(required(field))
            unless match && (match[1].to_i + 1) % 100 == match[2].to_i
              invalid("#{COLUMNS[field]} #{raw(field).inspect} isn't a season like 2026-27")
            end
            match[1].to_i
          end

          def position
            POSITIONS.include?(required(:position)) ? raw(:position) : invalid("Pos #{raw(:position).inspect} is unknown")
          end

          def dollars
            value = required(:cap_hit).delete("$,")
            value.match?(/\A\d+\z/) ? value.to_i : invalid("Cap Hit #{raw(:cap_hit).inspect} isn't a dollar amount")
          end

          def whole(field)
            match = /\A(\d+)(?:\.0+)?\z/.match(required(field))
            match ? match[1].to_i : invalid("#{COLUMNS[field]} #{raw(field).inspect} isn't a whole number")
          end

          def required(field)
            @values[field] || invalid("#{COLUMNS[field]} is blank")
          end

          def raw(field) = @values[field]

          def invalid(message)
            raise SourceChangedError.new("#{@where}: #{message}", source: :puckpedia)
          end
        end
      end
    end
  end
end
