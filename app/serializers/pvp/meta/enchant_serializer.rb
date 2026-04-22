module Pvp
  module Meta
    class EnchantSerializer
      def initialize(record, locale:)
        @record = record
        @locale = locale
      end

      def call
        { id: record.id, enchantment: serialize_enchantment_ref, slot: record.slot }
          .merge(serialize_usage)
      end

      private

        attr_reader :record, :locale

        def serialize_enchantment_ref
          {
            id:          record.enchantment.id,
            blizzard_id: record.enchantment.blizzard_id,
            name:        record.enchantment.t("name", locale: locale)
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
