module Pvp
  module Meta
    class ItemSerializer
      def initialize(record, locale:, crafting_stats: nil)
        @record         = record
        @locale         = locale
        @crafting_stats = crafting_stats
      end

      # rubocop:disable Metrics/AbcSize
      def call
        {
          id:                 record.id,
          item:               serialize_item_ref,
          slot:               record.slot,
          usage_count:        record.usage_count,
          usage_pct:          record.usage_pct.to_f,
          prev_usage_pct:     record.prev_usage_pct&.to_f,
          trend:              TrendClassifier.call(record.usage_pct, record.prev_usage_pct),
          snapshot_at:        record.snapshot_at,
          crafted:            crafting_stats.present?,
          top_crafting_stats: crafting_stats || []
        }
      end
      # rubocop:enable Metrics/AbcSize

      private

        attr_reader :record, :locale, :crafting_stats

        def serialize_item_ref
          {
            id:          record.item.id,
            blizzard_id: record.item.blizzard_id,
            name:        record.item.t("name", locale: locale),
            icon_url:    record.item.icon_url,
            quality:     record.item.quality
          }
        end
    end
  end
end
