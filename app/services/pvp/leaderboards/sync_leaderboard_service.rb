module Pvp
  module Leaderboards
    class SyncLeaderboardService < ApplicationService
      def initialize(season:, bracket:, region:, locale: "en_US", snapshot_at: Time.current)
        @season      = season
        @bracket     = bracket
        @region      = region
        @locale      = locale
        @snapshot_at = snapshot_at
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      def call
        res = Blizzard::Api::GameData::PvpSeason::Leaderboard.fetch(
          pvp_season_id: season.blizzard_id,
          bracket:       bracket,
          region:        region,
          locale:        locale
        )

        entries = res.fetch("entries", [])

        bracket_config = Pvp::BracketConfig.for(bracket)
        top_n      = bracket_config&.dig(:top_n)
        rating_min = bracket_config&.dig(:rating_min)

        # Primary limit: take top N entries (already sorted by rank from API)
        entries = entries.first(top_n) if top_n

        # Safety floor: filter by minimum rating
        entries.select! { |entry| entry["rating"].to_i >= rating_min } if rating_min

        character_ids = []

        # Upsert characters BEFORE acquiring the leaderboard lock so concurrent
        # bracket syncs (2v2 + 3v3 running in parallel) don't hold the row lock
        # while waiting on each other's character upserts.  Characters are
        # independent of the leaderboard row so no lock is needed here.
        character_records = entries.map do |entry_json|
          character_data  = entry_json.fetch("character")
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

        unique_character_records = character_records.uniq { |c| [ c[:blizzard_id], c[:region] ] }

        # rubocop:disable Rails/SkipsModelValidations
        upsert_result = Character.upsert_all(
          unique_character_records,
          unique_by: %i[blizzard_id region],
          returning: %i[blizzard_id id]
        )
        # rubocop:enable Rails/SkipsModelValidations

        char_id_map = upsert_result.rows.to_h { |row| [ row[0].to_s, row[1] ] }

        # rubocop:disable Metrics/BlockLength
        with_deadlock_retry do
          leaderboard = PvpLeaderboard.find_or_create_by!(
            pvp_season_id: season.id,
            bracket:       bracket,
            region:        region
          )

          leaderboard.with_lock do
            now = Time.current
            entry_records = entries.map do |entry_json|
              character_data = entry_json.fetch("character")
              stats          = entry_json.fetch("season_match_statistics")

              {
                pvp_leaderboard_id: leaderboard.id,
                character_id:       char_id_map[character_data["id"].to_s],
                rank:               entry_json["rank"],
                rating:             entry_json["rating"],
                wins:               stats["won"],
                losses:             stats["lost"],
                snapshot_at:        snapshot_at,
                created_at:         now,
                updated_at:         now
              }
            end

            # Deduplicate by character_id — shuffle-overall leaderboards return the
            # same character once per spec ranking.  Keep the best placement (lowest rank).
            entry_records = entry_records
              .group_by { |r| r[:character_id] }
              .transform_values { |dupes| dupes.min_by { |r| r[:rank] } }
              .values

            ActiveRecord::Base.transaction do
              # rubocop:disable Rails/SkipsModelValidations
              PvpLeaderboardEntry.insert_all!(entry_records)
              # rubocop:enable Rails/SkipsModelValidations

              character_ids = char_id_map.values
              leaderboard.update!(last_synced_at: snapshot_at)

              prune_old_entries(leaderboard.id, character_ids)
            end
          end
        end
        # rubocop:enable Metrics/BlockLength

        Rails.logger.info(
          "[SyncLeaderboardService] #{region}/#{bracket}: " \
          "#{entries.size} entries synced, #{character_ids.size} characters"
        )

        success(nil, context: { character_ids: character_ids, entry_count: entries.size })
      rescue => e
        failure(e)
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      private

        attr_reader :season, :bracket, :region, :locale, :snapshot_at

        def faction_enum(type)
          return nil unless type

          case type
          when "ALLIANCE" then 0
          when "HORDE"    then 1
          end
        end

        MAX_SNAPSHOTS_PER_CHARACTER = 3

        # Delete entries older than the N most recent snapshots per character
        # for the given leaderboard. Keeps the table from growing unbounded
        # since the real equipment/talent data lives on the characters.
        def prune_old_entries(leaderboard_id, character_ids)
          return if character_ids.empty?

          ranked = PvpLeaderboardEntry
            .select("id, ROW_NUMBER() OVER (PARTITION BY character_id ORDER BY snapshot_at DESC, id DESC) AS rn")
            .where(pvp_leaderboard_id: leaderboard_id, character_id: character_ids)

          keep_ids = PvpLeaderboardEntry
            .from(ranked, :ranked)
            .where("ranked.rn <= ?", MAX_SNAPSHOTS_PER_CHARACTER)
            .select("ranked.id")

          PvpLeaderboardEntry
            .where(pvp_leaderboard_id: leaderboard_id, character_id: character_ids)
            .where.not(id: keep_ids)
            .delete_all
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
end
