module Pvp
  module Meta
    class EnchantVariantMerger
      def self.call(serialized) = new(serialized).call

      def initialize(serialized)
        @serialized = serialized
      end

      def call
        serialized
          .group_by { |e| [ e[:slot], e[:enchantment][:name] ] }
          .map { |_, group| merge_group(group) }
          .sort_by { |e| -e[:usage_pct] }
      end

      private

        attr_reader :serialized

        def merge_group(group)
          return group.first if group.size == 1

          primary     = group.max_by { |e| e[:usage_pct] }
          merged_pct  = group.sum { |e| e[:usage_pct] }
          any_prev    = group.any? { |e| e[:prev_usage_pct] }
          merged_prev = any_prev ? group.sum { |e| e[:prev_usage_pct].to_f } : nil

          primary.merge(
            usage_count:    group.sum { |e| e[:usage_count] },
            usage_pct:      merged_pct,
            prev_usage_pct: merged_prev,
            trend:          TrendClassifier.call(merged_pct, merged_prev)
          )
        end
    end
  end
end
