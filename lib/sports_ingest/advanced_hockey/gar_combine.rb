# frozen_string_literal: true

module SportsIngest
  module AdvancedHockey
    # Merges EH GAR rows per player and season, for {SkaterGar.combine} and {GoalieGar.combine}.
    #
    # @api private
    module GarCombine
      module_function

      # Merges rows for the same player and season into one. Teams are joined in row order, and
      # every other field but the identifiers is summed (rounded to one decimal); a sum is +nil+
      # if any part is.
      #
      # @param rows [Array<Model>] rows with +player+, +season+, +teams+ and +position+ fields
      # @param model [Class] the row's model class, for its member list
      # @return [Array<Model>] one row per player and season, in order of first appearance
      def call(rows, model)
        rows.group_by { [it.player, it.season] }.values.map do |group|
          next group.first if group.one?

          sums = (model.members - %i[player season teams position]).to_h do |field|
            values = group.map(&field)
            [field, values.include?(nil) ? nil : values.sum.round(1)]
          end
          group.first.with(teams: group.flat_map(&:teams).uniq, **sums)
        end
      end
    end
  end
end
