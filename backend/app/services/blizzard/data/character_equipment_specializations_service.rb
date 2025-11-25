# app/services/blizzard/data/character_equipment_specializations_service.rb
module Blizzard
  module Data
    class CharacterEquipmentSpecializationsService
      attr_reader :talents, :active_specialization, :active_hero_tree, :class_slug

      def initialize(data)
        @specializations = Array(data["specializations"])
        @active_specialization = data["active_specialization"]
        @active_hero_tree = data["active_hero_talent_tree"]

        @talents = build_talents
      end

      def has_data?
        talents.is_a?(Hash) && talents.any?
      end

      private

        attr_reader :specializations

        def build_talents
          return {} unless active_specialization.present?

          active_spec = find_active_spec
          return {} unless active_spec

          loadout = active_loadout(active_spec)
          return {} unless loadout

          @class_slug = loadout.dig("selected_class_talent_tree", "name")&.downcase

          talent_trees = build_talent_trees(loadout)

          pvp_talents = active_spec["pvp_talent_slots"]

          talent_trees.merge(
            "pvp_talents":         pvp_talents,
            "talent_loadout_code": loadout["talent_loadout_code"] || ""
          ).stringify_keys!
        end

        def find_active_spec
          spec_name = active_specialization["name"]
          specializations.find { |sp| sp.dig("specialization", "name") == spec_name }
        end


        def active_loadout(spec)
          Array(spec["loadouts"]).find { |l| l["is_active"] }
        end

        def build_talent_trees(loadout)
          %w[class spec hero].each_with_object({}) do |type, acc|
            acc["#{type}_talents"] = extract_talent_tree(
              loadout["selected_#{type}_talents"]
            )
          end
        end

        def extract_talent_tree(talents)
          Array(talents).filter_map do |talent|
            info = talent.dig("tooltip", "talent")
            next unless info

            {
              id:   info["id"],
              name: info["name"],
              rank: talent["rank"]
            }
          end
        end
    end
  end
end
