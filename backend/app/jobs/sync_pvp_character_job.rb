class SyncPvpCharacterJob < ApplicationJob
  queue_as :default

  COMBAT_SLOTS = %w[
    HEAD NECK SHOULDER CHEST WAIST LEGS FEET
    WRIST HAND FINGER TRINKET CLOAK WEAPON OFF_HAND
  ].freeze

  def perform(region:, realm:, name:, entry_id:, locale: "en_US")
    entry = PvpLeaderboardEntry.find(entry_id)
    character = entry.character

    equipment = Blizzard::Api::Profile::CharacterEquipmentSummary.fetch(
      region:, name:, realm:, locale:
    )

    talents = Blizzard::Api::Profile::CharacterSpecializationSummary.fetch(
      region:, name:, realm:, locale:
    )

    enrich_entry_from_api(entry, character, equipment, talents)

  rescue Blizzard::Client::Error => e
    handle_blizzard_error(e, region:, realm:, name:, entry:)
  end

  # Same idea as enrich_entry_from_files, pero con payloads de la API
  def enrich_entry_from_api(entry, character, equipment_json, talents_json)
    update_data = {}

    equipped_items = Array(equipment_json["equipped_items"])

    valid_items = equipped_items.select do |item|
      slot_type = item.dig("inventory_type", "type") || item.dig("slot", "type")
      ilvl = item.dig("level", "value")

      COMBAT_SLOTS.include?(slot_type) && ilvl.to_i > 0
    end

    item_levels = valid_items.map { |i| i.dig("level", "value").to_i }

    avg_ilvl =
      if item_levels.any?
        (item_levels.sum.to_f / item_levels.size).round
      else
        nil
      end

    update_data[:gear_raw] = equipped_items
    update_data[:item_level] = avg_ilvl

    # Tier set
    set_block = equipped_items.map { |i| i["set"] }.compact.first
    if set_block
      update_data[:tier_set_id] = set_block.dig("item_set", "id")
      update_data[:tier_set_name] = set_block.dig("item_set", "name")

      pieces = (set_block["items"] || []).count { |x| x["is_equipped"] }
      update_data[:tier_set_pieces] = pieces

      effects = set_block["effects"] || []
      update_data[:tier_4p_active] =
        effects.any? { |eff| eff["required_count"] == 4 && eff["is_active"] }
    end

    # -------------------------
    # TALENTS
    # -------------------------
    specs = Array(talents_json["specializations"])

    active_spec =
      specs.find { |sp| Array(sp["loadouts"]).any? { |l| l["is_active"] } } ||
      specs.first

    if active_spec
      spec_info = active_spec["specialization"] || {}
      update_data[:spec] = spec_info["name"]
      update_data[:spec_id] = spec_info["id"]

      # hero tree
      hero_tree = active_spec["active_hero_talent_tree"] || {}
      update_data[:hero_talent_tree_id] = hero_tree["id"]
      update_data[:hero_talent_tree_name] = hero_tree["name"]

      # pvp talents
      pvp_talents = Array(active_spec["pvp_talent_slots"]).map do |slot|
        t = slot.dig("selected", "talent")
        t && { "id" => t["id"], "name" => t["name"] }
      end.compact

      loadout =
        Array(active_spec["loadouts"]).find { |l| l["is_active"] } ||
        Array(active_spec["loadouts"]).first

      class_talents = Array(loadout["selected_class_talents"]).map do |t|
        info = t.dig("tooltip", "talent") || {}
        { "id" => info["id"], "name" => info["name"], "rank" => t["rank"] }
      end

      spec_talents = Array(loadout["selected_spec_talents"]).map do |t|
        info = t.dig("tooltip", "talent") || {}
        { "id" => info["id"], "name" => info["name"], "rank" => t["rank"] }
      end

      hero_talents = Array(loadout["selected_hero_talents"]).map do |t|
        info = t.dig("tooltip", "talent") || {}
        { "id" => info["id"], "name" => info["name"], "rank" => t["rank"] }
      end

      update_data[:talents_raw] = {
        "pvp_talents" => pvp_talents,
        "class_talents" => class_talents,
        "spec_talents" => spec_talents,
        "hero_talents" => hero_talents
      }
    end

    return if update_data.empty?

    Rails.logger.silence do
      entry.update!(update_data)
    end
  end

  def handle_blizzard_error(e, region:, realm:, name:, entry:)
    message = e.message

    if message.include?("404")
      Rails.logger.warn(
        "[SyncPvpCharacterJob] 404 for profile " \
          "region=#{region} realm=#{realm} name_original='#{name}' entry_id=#{entry.id}"
      )
      return
    end

    Rails.logger.error(
      "[SyncPvpCharacterJob] Error for region=#{region} realm=#{realm} name='#{name}' entry_id=#{entry.id}: #{message}"
    )
    raise error
  end
end
