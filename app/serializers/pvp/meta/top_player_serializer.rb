module Pvp
  module Meta
    class TopPlayerSerializer
      def initialize(row)
        @row = row
      end

      def call
        {
          name:       @row.name,
          realm:      format_realm(@row.realm),
          region:     format_region(@row.region),
          rating:     @row.rating,
          wins:       @row.wins,
          losses:     @row.losses,
          rank:       @row.rank,
          score:      @row.score.to_f,
          avatar_url: CdnProxy.rewrite(@row.avatar_url),
          class_slug: @row.class_slug
        }
      end

      private

        def format_realm(realm)
          realm.to_s.tr("-", " ").titleize
        end

        def format_region(region)
          region.to_s.upcase
        end
    end
  end
end
