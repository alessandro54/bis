module Pvp
  module Meta
    class ClassDistributionService
      def initialize(season:, bracket:, region:)
        @season = season
        @bracket = bracket
        @region = region
      end

      def call
        counts = base_scope
                   .reorder(nil)
                   .group(
                     "pvp_leaderboard_entries.spec_id",
                     "characters.class_id",
                     "characters.class_slug"
                   )
                   .pluck(
                     "pvp_leaderboard_entries.spec_id",
                     "characters.class_id",
                     "characters.class_slug",
                     Arel.sql("COUNT(*) AS count"),
                     Arel.sql("AVG(pvp_leaderboard_entries.rating) AS avg_rating")
                   )

        rows = counts.map do |spec_id, class_id, class_slug, count, avg_rating|
          role = ::Wow::Roles.role_for(class_id: class_id.to_i, spec_id:)
          {
            class:       class_slug,
            spec:        ::Wow::Specs.slug_for(spec_id),
            count:       count,
            role:        role,
            mean_rating: avg_rating.to_f.round(2)
          }
        end

        rows.select! { |row| row[:role] == :dps }

        total = rows.sum { |row| row[:count] }

        rows.map do |row|
          row.merge(
            percentage: total.positive? ? ((row[:count].to_f / total) * 100).round(2) : 0.0
          )
        end.sort_by { |row| [ -row[:count], -row[:mean_rating].to_f ] }
      end

      private

        attr_reader :season, :bracket, :region

        def base_scope
          PvpLeaderboardEntry
            .joins(:character, :pvp_leaderboard)
            .where(
              pvp_leaderboards: {
                pvp_season_id: season.id,
                bracket:       bracket,
                region:        region
              }
            )
            .where("pvp_leaderboard_entries.snapshot_at > ?", 1.day.ago)
            .where.not("pvp_leaderboard_entries.spec_id": nil,
                       "characters.class_id":             nil)
            .select("DISTINCT ON (character_id) pvp_leaderboard_entries.*")
            .order("character_id, snapshot_at DESC")
        end
    end
  end
end
