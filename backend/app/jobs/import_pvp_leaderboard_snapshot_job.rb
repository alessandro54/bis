COMBAT_SLOTS = %w[
  HEAD NECK SHOULDER CHEST WAIST LEGS FEET
  WRIST HAND FINGER TRINKET CLOAK WEAPON OFF_HAND
].freeze

class ImportPvpLeaderboardSnapshotJob < ApplicationJob
  queue_as :default

  # file_path: JSON de leaderboard
  # profiles_dir: JSONs de equipment/talents por personaje
  #
  # Esperamos archivos:
  #   <id>_equipment.json
  #   <id>_talents.json
  #
  def perform(file_path, profiles_dir: Rails.root.join("tmp", "dumps").to_s)
    payload = JSON.parse(File.read(file_path))

    season_blizzard_id = payload.dig("season", "id")
    bracket_name       = payload["name"]
    region             = "us"

    ActiveRecord::Base.transaction do
      season      = import_season(season_blizzard_id)
      leaderboard = import_leaderboard(season, bracket_name, region)

      snapshot_time = Time.current

      Array(payload["entries"]).each do |entry_json|
        character, entry = import_entry(entry_json, leaderboard, region, snapshot_time)
        enrich_entry_from_files(entry, character, profiles_dir)
      end

      leaderboard.update!(last_synced_at: snapshot_time)
    end
  end

  # ============================================================
  #  SEASON
  # ============================================================

  def import_season(season_blizzard_id)
    PvpSeason.find_or_create_by!(blizzard_id: season_blizzard_id) do |s|
      s.display_name = "Season #{season_blizzard_id} (dummy)"
      s.start_time   = rand(30..120).days.ago
      s.end_time     = nil
      s.is_current   = true
    end
  end

  # ============================================================
  #  LEADERBOARD
  # ============================================================

  def import_leaderboard(season, bracket_name, region)
    PvpLeaderboard.find_or_create_by!(
      pvp_season: season,
      bracket: bracket_name,
      region: region
    )
  end

  # ============================================================
  #  ENTRY + CHARACTER
  # ============================================================

  def import_entry(entry_json, leaderboard, region, snapshot_time)
    character_data = entry_json.fetch("character")
    stats          = entry_json.fetch("season_match_statistics")

    character = Character.find_or_initialize_by(
      blizzard_id: character_data["id"].to_s,
      region: region
    )

    character.name  = character_data["name"]
    character.realm = character_data.dig("realm", "slug")

    if character.respond_to?(:faction=)
      character.faction = faction_enum(entry_json.dig("faction", "type"))
    end

    character.save! if character.changed?

    entry = PvpLeaderboardEntry.create!(
      pvp_leaderboard: leaderboard,
      character: character,
      rank: entry_json["rank"],
      rating: entry_json["rating"],
      wins: stats["won"],
      losses: stats["lost"],
      snapshot_at: snapshot_time,
      class_id: character.class_id,
      spec_id: nil,
      spec: nil,
      item_level: nil,
      gear_raw: nil,
      talents_raw: nil,
      hero_talent_tree_id: nil,
      hero_talent_tree_name: nil,
      tier_set_id: nil,
      tier_set_name: nil,
      tier_set_pieces: nil,
      tier_4p_active: false
    )

    [ character, entry ]
  end

  # ============================================================
  #  ENRICHMENT
  # ============================================================

  def enrich_entry_from_files(entry, character, profiles_dir)
    equipment_path = File.join(profiles_dir, "#{character.name.downcase}_equipment.json")
    talents_path   = File.join(profiles_dir, "#{character.name.downcase}_talents.json")

    Rails.logger.info("equipment_path: #{equipment_path}")
    Rails.logger.info("talents_path:   #{talents_path}")

    update_data = {}

    # -------------------------
    # EQUIPMENT
    # -------------------------
    if File.exist?(equipment_path)
      gear = JSON.parse(File.read(equipment_path))
      equipped_items = gear["equipped_items"] || []

      # item level
      valid_items = equipped_items.select do |item|
        slot_type = item.dig("inventory_type", "type") || item.dig("slot", "type")
        ilvl      = item.dig("level", "value")

        COMBAT_SLOTS.include?(slot_type) && ilvl.to_i > 0
      end

      item_levels = valid_items.map { |i| i.dig("level", "value").to_i }

      avg_ilvl =
        if item_levels.any?
          (item_levels.sum.to_f / item_levels.size).round
        else
          nil
        end

      update_data[:gear_raw]   = equipped_items
      update_data[:item_level] = avg_ilvl

      # Tier Set
      set_block = equipped_items.map { |i| i["set"] }.compact.first
      if set_block
        update_data[:tier_set_id]   = set_block.dig("item_set", "id")
        update_data[:tier_set_name] = set_block.dig("item_set", "name")

        pieces = (set_block["items"] || []).count { |x| x["is_equipped"] }
        update_data[:tier_set_pieces] = pieces

        effects = set_block["effects"] || []
        update_data[:tier_4p_active] =
          effects.any? { |eff| eff["required_count"] == 4 && eff["is_active"] }
      end
    end

    # -------------------------
    # TALENTS
    # -------------------------
    if File.exist?(talents_path)
      spec_json = JSON.parse(File.read(talents_path))

      specs = spec_json["specializations"] || []

      active_spec =
        specs.find { |sp| Array(sp["loadouts"]).any? { |l| l["is_active"] } } ||
        specs.first

      if active_spec
        spec_info = active_spec["specialization"] || {}
        update_data[:spec]    = spec_info["name"]
        update_data[:spec_id] = spec_info["id"]

        # hero tree
        hero_tree = active_spec["active_hero_talent_tree"] || {}
        update_data[:hero_talent_tree_id]   = hero_tree["id"]
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
          "pvp_talents"   => pvp_talents,
          "class_talents" => class_talents,
          "spec_talents"  => spec_talents,
          "hero_talents"  => hero_talents
        }
      end
    end

    entry.update!(update_data) if update_data.any?
  end

  # ============================================================
  # HELPERS
  # ============================================================

  def faction_enum(type)
    return nil unless type

    case type
    when "ALLIANCE" then 1
    when "HORDE"    then 2
    else nil
    end
  end
end
