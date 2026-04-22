module Pvp
  module Meta
    class CraftingStatsQuery
      def initialize(item_ids, season:, bracket:, spec_id:)
        @item_ids = item_ids
        @season   = season
        @bracket  = bracket
        @spec_id  = spec_id
      end

      def call
        return {} if item_ids.empty?

        rows = CharacterItem
          .joins(character: { pvp_leaderboard_entries: :pvp_leaderboard })
          .where(pvp_leaderboards: { bracket:, pvp_season: season })
          .where(pvp_leaderboard_entries: { spec_id: })
          .where(item_id: item_ids)
          .where("crafting_stats <> '{}'")
          .group(:item_id, :crafting_stats)
          .order(Arel.sql("COUNT(*) DESC"))
          .pluck(:item_id, :crafting_stats)

        rows.each_with_object({}) do |(item_id, stats), result|
          result[item_id] ||= stats
        end
      end

      private

        attr_reader :item_ids, :season, :bracket, :spec_id
    end
  end
end
