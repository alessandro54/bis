module Pvp
  module Meta
    class GemSerializer
      def initialize(record, locale:)
        @record = record
        @locale = locale
      end

      def call
        { id: record.id, item: serialize_item_ref, slot: record.slot, socket_type: record.socket_type }
          .merge(serialize_usage)
      end

      private

        attr_reader :record, :locale

        def serialize_item_ref
          {
            id:          record.item.id,
            blizzard_id: record.item.blizzard_id,
            name:        record.item.t("name", locale: locale),
            icon_url:    record.item.icon_url,
            quality:     record.item.quality
          }
        end

        def serialize_usage
          {
            usage_count:    record.usage_count,
            usage_pct:      record.usage_pct.to_f,
            prev_usage_pct: record.prev_usage_pct&.to_f,
            trend:          TrendClassifier.call(record.usage_pct, record.prev_usage_pct),
            snapshot_at:    record.snapshot_at
          }
        end
    end
  end
end
