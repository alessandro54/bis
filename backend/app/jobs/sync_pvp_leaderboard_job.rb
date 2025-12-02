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

    bracket_config = Pvp::BracketConfig.for(bracket)
    rating_min = bracket_config&.dig(:rating_min)
    job_queue = bracket_config&.dig(:job_queue) || :character_sync

    if rating_min
      entries = entries.select { |entry| entry["rating"].to_i >= rating_min }
    end

    with_deadlock_retry do
      ActiveRecord::Base.transaction do
        leaderboard = PvpLeaderboard.find_or_create_by!(
          pvp_season_id: season.id,
          bracket:       bracket,
          region:        region,
          )

        entries.each do |entry_json|
          character, _entry = import_entry(entry_json, leaderboard, region, snapshot_time)

          SyncPvpCharacterJob
            .set(queue: job_queue)
            .perform_later(
              character_id: character.id,
              locale:       locale
            )
        end

        leaderboard.update!(last_synced_at: snapshot_time)
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

    entry = PvpLeaderboardEntry.create!(
      pvp_leaderboard: leaderboard,
      character:       character,
      rank:            entry_json["rank"],
      rating:          entry_json["rating"],
      wins:            stats["won"],
      losses:          stats["lost"],
      snapshot_at:     snapshot_time,
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
