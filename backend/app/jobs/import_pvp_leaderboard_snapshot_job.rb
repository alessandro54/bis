# ImportPvpLeaderboardSnapshotJob.perform_now(Rails.root.join("tmp", "dumps", "2v2.json").to_s)

class ImportPvpLeaderboardSnapshotJob < ApplicationJob
  queue_as :default

  def perform(file_path)
    payload = JSON.parse(File.read(file_path))

    season_blizzard_id = payload.dig("season", "id")

    bracket_name = payload["name"]

    region = "us"

    ActiveRecord::Base.transaction do
      season = find_or_create_season(season_blizzard_id)
      leaderboard = find_or_create_leaderboard(season, bracket_name, region)

      snapshot_time = Time.current

      Array(payload["entries"]).each do |entry_json|
        character, entry = import_entry(entry_json, leaderboard, region, snapshot_time)

        enrich_from_profile_file(entry, character)
      end


      leaderboard.update!(last_synced_at: snapshot_time)
    end
  end

  private

  def find_or_create_season(blizzard_id)
    PvpSeason.find_or_create_by!(blizzard_id:) do |season|
      season.display_name = "Season #{blizzard_id}"

      start_offset_days = rand(30..120)

      season.start_time = start_offset_days.days.ago

      season.end_time = nil

      season.is_current = true
    end
  end

  def find_or_create_leaderboard(season, bracket_name, region)
    PvpLeaderboard.find_or_create_by!(
      pvp_season: season,
      bracket: bracket_name,
      region: region
    )
  end

  def import_entry(entry, leaderboard, region, snapshot_time)
    character_data = entry.fetch("character")
    stats = entry.fetch("season_match_statistics")

    character = Character.find_or_initialize_by(
      blizzard_id: character_data["id"],
      region: region
    )

    character.name  = character_data["name"]
    character.realm = character_data.dig("realm", "slug")
    character.faction = faction_enum(entry.dig("faction", "type")) if character.respond_to?(:faction=)

    character.save! if character.changed?

    pvp_entry = PvpLeaderboardEntry.create!(
      pvp_leaderboard: leaderboard,
      character: character,
      rank: entry["rank"],
      rating: entry["rating"],
      wins: stats["won"],
      losses: stats["lost"],
      snapshot_at: snapshot_time,
      class_id: character.class_id,
      spec_id: nil,
      spec: nil,
      item_level: nil,
      gear_raw: nil,
      talents_raw: nil
    )

    [ character, pvp_entry ]
  end

  def enrich_from_profile_file(entry, character)
    equipment_path = File.join(Rails.root.join("tmp", "dumps", "nystinn.json").to_s)
    talents_path = File.join(Rails.root.join("tmp", "dumps", "nystinn_summary.json").to_s)

    update_data = {}

    if File.exist?(equipment_path)
      gear = JSON.parse(File.read(equipment_path))
      equipped_items = gear["equipped_items"] || []

      item_levels = equipped_items.map { |i| i.dig("level", "value") }.compact
      avg_item_level =
        item_levels.any? ? (item_levels.sum.to_f / item_levels.size).round : nil

      update_data[:gear_raw]   = equipped_items
      update_data[:item_level] = avg_item_level
    end

    if File.exist?(talents_path)
      talents = JSON.parse(File.read(talents_path))

      specs = talents["specializations"] || []

      active_spec = specs.find do |spec|
        Array(spec["loadouts"]).any? { |loadout| loadout["is_active"] }
      end || specs.first

      if active_spec
        spec_info = active_spec["specialization"] || {}
        spec_name = spec_info["name"]
        spec_id   = spec_info["id"]

        pvp_talents = Array(active_spec["pvp_talent_slots"]).map do |slot|
          talent = slot.dig("selected", "talent")
          next unless talent
          {
            "id"   => talent["id"],
            "name" => talent["name"]
          }
        end.compact

        loadout = Array(active_spec["loadouts"]).find { |l| l["is_active"] } ||
                  Array(active_spec["loadouts"]).first

        # class talents
        class_talents = Array(loadout["selected_class_talents"]).map do |t|
          talent_info = t.dig("tooltip", "talent") || {}
          {
            "id"   => talent_info["id"],
            "name" => talent_info["name"],
            "rank" => t["rank"]
          }
        end

        spec_talents = Array(loadout["selected_spec_talents"]).map do |t|
          talent_info = t.dig("tooltip", "talent") || {}
          {
            "id"   => talent_info["id"],
            "name" => talent_info["name"],
            "rank" => t["rank"]
          }
        end

        hero_talents = Array(loadout["selected_hero_talents"]).map do |t|
          talent_info = t.dig("tooltip", "talent") || {}
          {
            "id"   => talent_info["id"],
            "name" => talent_info["name"],
            "rank" => t["rank"]
          }
        end

        update_data[:spec]    = spec_name
        update_data[:spec_id] = spec_id
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

  def faction_enum(type)
    return nil unless type

    case type
    when "ALLIANCE" then 0
    when "HORDE"    then 1
    else nil
    end
  end
end
