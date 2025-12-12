module Pvp
  class SyncLeaderboardJob < ApplicationJob
    queue_as :default

    def perform(region: "us", season:, bracket:, locale: "en_US")
      res = Blizzard::Api::GameData::PvpSeason::Leaderboard.fetch(
        pvp_season_id: season.blizzard_id,
        bracket:,
        region:,
        locale:
      )

      entries = res.fetch("entries", []).first(100)
      snapshot_time = Time.current

      bracket_config = Pvp::BracketConfig.for(bracket)
      rating_min = bracket_config&.dig(:rating_min)
      job_queue = bracket_config&.dig(:job_queue) || :character_sync

      if rating_min
        entries = entries.select { |entry| entry["rating"].to_i >= rating_min }
      end

      with_deadlock_retry do
        leaderboard = PvpLeaderboard.find_or_create_by!(
          pvp_season_id: season.id,
          bracket:       bracket,
          region:        region,
        )

        # Prepare bulk character data for upsert
        character_records = entries.map do |entry_json|
          character_data = entry_json.fetch("character")
          character_attrs = {
            blizzard_id: character_data["id"].to_s,
            region:      region,
            name:        character_data["name"],
            realm:       character_data.dig("realm", "slug")
          }

          if Character.new.respond_to?(:faction=)
            character_attrs[:faction] = faction_enum(entry_json.dig("faction", "type"))
          end

          character_attrs
        end

        # Bulk upsert all characters at once
        Character.upsert_all(
          character_records,
          unique_by: %i[blizzard_id region],
          returning: false
        )

        # Bulk create leaderboard entries
        ActiveRecord::Base.transaction do
          character_ids = Character.where(
            blizzard_id: character_records.map { |c| c[:blizzard_id] },
            region: region
          ).pluck(:blizzard_id, :id).to_h

          entry_records = entries.map do |entry_json|
            character_data = entry_json.fetch("character")
            stats = entry_json.fetch("season_match_statistics")

            {
              pvp_leaderboard_id: leaderboard.id,
              character_id: character_ids[character_data["id"].to_s],
              rank: entry_json["rank"],
              rating: entry_json["rating"],
              wins: stats["won"],
              losses: stats["lost"],
              snapshot_at: snapshot_time,
              created_at: Time.current,
              updated_at: Time.current
            }
          end

          PvpLeaderboardEntry.insert_all!(entry_records)

          # Enqueue character sync jobs for all characters
          character_ids.values.each do |character_id|
            SyncCharacterJob
              .set(queue: job_queue)
              .perform_later(
                character_id: character_id,
                locale: locale
              )
          end

          leaderboard.update!(last_synced_at: snapshot_time)
        end
      end
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
end
