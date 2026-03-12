module Pvp
  module Characters
    # Computes total secondary stat ratings for a character's equipped gear
    # by summing item base stats, socket gem display strings, and enchant names.
    # Returns e.g. { "HASTE_RATING" => 197, "CRIT_RATING" => 27, ... }
    class ComputeStatTotalsService < BaseService
      SECONDARY_STATS = %w[HASTE_RATING CRIT_RATING MASTERY_RATING VERSATILITY].freeze

      STAT_PATTERNS = {
        "HASTE_RATING" => /\+(\d+)\s+Haste/i,
        "CRIT_RATING" => /\+(\d+)\s+Crit/i,
        "MASTERY_RATING" => /\+(\d+)\s+Mastery/i,
        "VERSATILITY" => /\+(\d+)\s+Versatil/i
      }.freeze

      def initialize(character:, spec_id:)
        @character = character
        @spec_id   = spec_id
      end

      def call
        items = character.character_items.where(spec_id: spec_id)
        return success({}) if items.empty?

        enchant_names = fetch_enchant_names(items.filter_map(&:enchantment_id))
        totals        = Hash.new(0)

        items.each do |item|
          add_item_stats(item, totals)
          add_gem_stats(item, totals)
          add_enchant_stats(item, enchant_names, totals)
        end

        success(totals.select { |_, v| v > 0 })
      end

      private

        attr_reader :character, :spec_id

        def add_item_stats(item, totals)
          return unless item.stats.is_a?(Hash)

          item.stats.each do |stat, value|
            totals[stat] += value.to_i if SECONDARY_STATS.include?(stat)
          end
        end

        def add_gem_stats(item, totals)
          Array(item.sockets).each do |socket|
            parse_stat_string(socket["display_string"], totals)
          end
        end

        def add_enchant_stats(item, enchant_names, totals)
          return unless item.enchantment_id

          parse_stat_string(enchant_names[item.enchantment_id], totals)
        end

        def parse_stat_string(str, totals)
          return if str.blank?

          STAT_PATTERNS.each do |stat, regex|
            totals[stat] += $1.to_i if str.match(regex)
          end
        end

        # Batch-load enchantment names (translation value) for a list of enchantment DB IDs.
        def fetch_enchant_names(enchantment_ids)
          return {} if enchantment_ids.empty?

          Translation
            .where(translatable_type: "Enchantment", translatable_id: enchantment_ids, key: "name")
            .pluck(:translatable_id, :value)
            .to_h
        end
    end
  end
end
