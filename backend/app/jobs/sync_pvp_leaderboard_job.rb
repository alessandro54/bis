class SyncPvpLeaderboardJob < ApplicationJob
  queue_as :default

  def perform(region: "us", season:, bracket:, locale: "en_US")
    res = Blizzard::Api::GameData::PvpSeason::Leaderboard.fetch(
      pvp_season_id: season.blizzard_id,
      bracket:,
      region:,
      locale:
    )

    entries = res.fetch("entries", []).first(50)
    snapshot_time = Time.current

    entries_for_jobs = []

    ActiveRecord::Base.transaction do
      leaderboard = PvpLeaderboard.find_or_create_by!(
        pvp_season_id: season.id,
        bracket: bracket,
        region:,
      )

      entries.each do |entry_json|
        _character, entry = import_entry(entry_json, leaderboard, region, snapshot_time)
        entries_for_jobs << entry
      end
    end

    entries_for_jobs.each do |entry|
      SyncPvpCharacterJob.perform_later(
        region: region,
        locale: locale,
        realm: entry.character.realm,
        name: entry.character.name,
        entry_id: entry.id
      )
    end
  end

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

  private

    def faction_enum(type)
      return nil unless type

      case type
      when "ALLIANCE" then 0
      when "HORDE"    then 1
      else nil
      end
    end
end
