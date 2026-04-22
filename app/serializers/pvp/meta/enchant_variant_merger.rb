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
          return group.first.dup if group.size == 1

          merge_multiple_variants(group)
        end

        def merge_multiple_variants(group)
          primary     = group.max_by { |e| e[:usage_pct] }
          merged_pct  = group.sum { |e| e[:usage_pct] }
          merged_prev = compute_merged_prev(group)

          primary.merge(
            usage_count:    group.sum { |e| e[:usage_count] },
            usage_pct:      merged_pct,
            prev_usage_pct: merged_prev,
            trend:          TrendClassifier.call(merged_pct, merged_prev)
          )
        end

        def compute_merged_prev(group)
          return nil unless group.any? { |e| e[:prev_usage_pct] }

          group.sum { |e| e[:prev_usage_pct].to_f }
        end
    end
  end
end
