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

      Array(payload["entries"]).each do |entry|
        import_entry(entry, leaderboard, region, snapshot_time)
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
