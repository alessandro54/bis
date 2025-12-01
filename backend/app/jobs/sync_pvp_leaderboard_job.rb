class SyncPvpLeaderboardJob < ApplicationJob
  queue_as :default

  def perform(region: "us", season:, bracket:, locale: "en_US")
    res = Blizzard::Api::GameData::PvpSeason::Leaderboard.fetch(
      pvp_season_id: season.blizzard_id,
      bracket:,
      region:,
      locale:
    )

    entries = res.fetch("entries", [])
    snapshot_time = Time.current

    with_deadlock_retry do
      ActiveRecord::Base.transaction do
        leaderboard = PvpLeaderboard.find_or_create_by!(
          pvp_season_id: season.id,
          bracket:       bracket,
          region:,
          )

        entries.each do |entry_json|
          entry = import_entry(entry_json, leaderboard, region, snapshot_time)

          SyncPvpCharacterJob.perform_later(
            region:   region,
            locale:   locale,
            realm:    entry.character.realm,
            name:     entry.character.name,
            entry_id: entry.id
          )
        end
      end
    end
  end

  def import_entry(entry_json, leaderboard, region, snapshot_time)
    character_data = entry_json.fetch("character")
    stats          = entry_json.fetch("season_match_statistics")

    character_attrs = {
      blizzard_id: character_data["id"].to_s,
      region:      region,
      name:        character_data["name"],
      realm:       character_data.dig("realm", "slug")
    }

    if Character.new.respond_to?(:faction=)
      character_attrs[:faction] = faction_enum(entry_json.dig("faction", "type"))
    end

    Character.upsert(
      character_attrs,
      unique_by: %i[blizzard_id region]
    )

    character = Character.find_by!(
      blizzard_id: character_data["id"].to_s,
      region:
    )

    character.save! if character.changed?

    PvpLeaderboardEntry.create!(
      pvp_leaderboard:       leaderboard,
      character:             character,
      rank:                  entry_json["rank"],
      rating:                entry_json["rating"],
      wins:                  stats["won"],
      losses:                stats["lost"],
      snapshot_at:           snapshot_time,
      spec_id:               nil,
      item_level:            nil,
      raw_equipment:         nil,
      raw_specialization:    nil,
      hero_talent_tree_id:   nil,
      hero_talent_tree_name: nil,
      tier_set_id:           nil,
      tier_set_name:         nil,
      tier_set_pieces:       nil,
      tier_4p_active:        false
    )
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

    def with_deadlock_retry(max_retries: 3)
      retries = 0

      begin
        yield
      rescue ActiveRecord::Deadlocked
        retries += 1
        raise if retries > max_retries

        sleep(rand * 0.1)
        retry
      end
    end
end
