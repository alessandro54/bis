class SyncPvpCharacterJob < ApplicationJob
  queue_as :default

  COMBAT_SLOTS = %w[
    HEAD NECK SHOULDER CHEST WAIST LEGS FEET
    WRIST HAND FINGER TRINKET CLOAK WEAPON OFF_HAND
  ].freeze

  def perform(region:, realm:, name:, entry_id:, locale: "en_US")
    entry = PvpLeaderboardEntry.find(entry_id)
    character = entry.character

    equipment_json = safe_fetch do
      Blizzard::Api::Profile::CharacterEquipmentSummary.fetch(
        region:, realm:, name:, locale:
      )
    end
    return unless equipment_json

    talents_json = safe_fetch do
      Blizzard::Api::Profile::CharacterSpecializationSummary.fetch(
        region:, realm:, name:, locale:
      )
    end
    return unless talents_json

    enrich_entry_from_api(entry, character, equipment_json, talents_json)
  end

  private

    def safe_fetch
      yield
    rescue Blizzard::Client::Error => e
      handle_blizzard_error(e)
      nil
    end

    def enrich_entry_from_api(entry, character, equipment_json, talents_json)
      update_data = {}

      equipped_items = Array(equipment_json["equipped_items"])

      valid_items = equipped_items.select do |item|
        slot_type = item.dig("inventory_type", "type") || item.dig("slot", "type")
        ilvl = item.dig("level", "value")
        COMBAT_SLOTS.include?(slot_type) && ilvl.to_i > 0
      end

      ilvls = valid_items.map { |i| i.dig("level", "value").to_i }
      update_data[:item_level] = ilvls.any? ? (ilvls.sum.to_f / ilvls.size).round : nil
      update_data[:gear_raw] = equipped_items

      apply_tier_set(update_data, equipped_items)
      apply_talents(update_data, character, talents_json)

      return if update_data.empty?

      Rails.logger.silence { entry.update!(update_data) }
    end

    def apply_tier_set(update_data, items)
      block = items.map { |i| i["set"] }.compact.first
      return unless block

      update_data[:tier_set_id]      = block.dig("item_set", "id")
      update_data[:tier_set_name]    = block.dig("item_set", "name")
      update_data[:tier_set_pieces]  = (block["items"] || []).count { |x| x["is_equipped"] }

      effects = block["effects"] || []
      update_data[:tier_4p_active] = effects.any? { |eff| eff["required_count"] == 4 && eff["is_active"] }
    end

    def apply_talents(update_data, character, talents_json)
      spec_service = Blizzard::Data::CharacterEquipmentSpecializationsService.new(talents_json)
      return unless spec_service.has_data?

      update_data[:spec] = spec_service.active_specialization["name"].downcase
      update_data[:spec_id] = spec_service.active_specialization["id"]

      update_data[:hero_talent_tree_name] = spec_service.active_hero_tree["name"].downcase
      update_data[:hero_talent_tree_id] = spec_service.active_hero_tree["id"]

      character.update!(class_slug: spec_service.class_slug) if spec_service.class_slug.present?

      update_data[:talents_raw] = spec_service.talents
    end

    def handle_blizzard_error(e)
      if e.message.include?("404")
        Rails.logger.warn("[SyncPvpCharacterJob] 404 → profile private or deleted")
      else
        Rails.logger.error("[SyncPvpCharacterJob] Error: #{e.message}")
      end
    end
end
