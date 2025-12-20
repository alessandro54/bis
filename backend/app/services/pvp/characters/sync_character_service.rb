module Pvp
  module Characters
    class SyncCharacterService < ApplicationService
      DEFAULT_TTL_HOURS = ENV.fetch("PVP_EQUIPMENT_SNAPSHOT_TTL_HOURS", 24).to_i

      def initialize(character:, locale: "en_US", ttl_hours: DEFAULT_TTL_HOURS, processing_queues: nil)
        @character = character
        @locale = locale
        @ttl_hours = ttl_hours
        @processing_queues = processing_queues
      end

      def call
        return success(nil, context: { status: :not_found }) unless character
        return success(nil, context: { status: :skipped_private }) if character.is_private

        entries = latest_entries_per_bracket
        return success(nil, context: { status: :no_entries }) if entries.empty?

        snapshot = last_equipment_snapshot

        if reusable_snapshot?(snapshot)
          reuse_snapshot_for_entries(snapshot, entries)
          return success(entries, context: { status: :reused_snapshot })
        end

        equipment_json, talents_json = fetch_remote_data
        return success(nil, context: { status: :equipment_unavailable }) unless equipment_json
        return success(nil, context: { status: :talents_unavailable }) unless talents_json

        apply_fresh_snapshot(entries, equipment_json, talents_json)
        success(entries, context: { status: :applied_fresh_snapshot })
      rescue => e
        failure(e)
      end

      private

        attr_reader :character, :locale, :ttl_hours

        def last_equipment_snapshot
          ::Pvp::Characters::LastEquipmentSnapshotFinderService.call(
            character_id: character.id,
            ttl_hours:    ttl_hours
          )
        end

        def reusable_snapshot?(snapshot)
          snapshot.present? &&
            snapshot.raw_equipment.present? &&
            snapshot.raw_specialization.present? &&
            snapshot.equipment_processed_at.present? &&
            snapshot.specialization_processed_at.present?
        end

        def reuse_snapshot_for_entries(snapshot, entries)
          Rails.logger.silence do
            entries.each do |entry|
              copy_from_snapshot(snapshot, entry)
            end
          end
        end

        def apply_fresh_snapshot(entries, equipment_json, talents_json)
          logger.info(
            "[SyncCharacterService] Fetched fresh snapshot for character #{entries.first.character_id} " \
              "and applying to #{entries.size} latest entries per bracket"
          )

          Rails.logger.silence do
            entry_ids = []
            entries.each do |entry|
              entry.update!(
                raw_equipment:      equipment_json,
                raw_specialization: talents_json
              )

              entry_ids << entry.id
            end

            Pvp::ProcessLeaderboardEntryBatchJob.perform_later(entry_ids: entry_ids, locale: locale)
          end
        end

        def copy_from_snapshot(source, target)
          logger.info(
            "[SyncCharacterService] Reusing equipment snapshot from entry #{source.id} " \
              "for entry #{target.id}"
          )

          target.update!(
            raw_equipment:               source.raw_equipment,
            raw_specialization:          source.raw_specialization,
            item_level:                  source.item_level,
            tier_set_id:                 source.tier_set_id,
            tier_set_name:               source.tier_set_name,
            tier_set_pieces:             source.tier_set_pieces,
            tier_4p_active:              source.tier_4p_active,
            equipment_processed_at:      source.equipment_processed_at,
            spec_id:                     source.spec_id,
            hero_talent_tree_name:       source.hero_talent_tree_name,
            hero_talent_tree_id:         source.hero_talent_tree_id,
            specialization_processed_at: source.specialization_processed_at
          )
        end

        def safe_fetch
          yield
        rescue Blizzard::Client::Error => e
          handle_blizzard_error(e)
          nil
        end

        def fetch_equipment_json
          Blizzard::Api::Profile::CharacterEquipmentSummary.fetch(
            region: character.region,
            realm:  character.realm,
            name:   character.name,
            locale: locale
          )
        end

        def fetch_talents_json
          Blizzard::Api::Profile::CharacterSpecializationSummary.fetch(
            region: character.region,
            realm:  character.realm,
            name:   character.name,
            locale: locale
          )
        end

        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        def fetch_remote_data
          equipment_json = nil
          talents_json   = nil

          threads = []

          threads << Thread.new do
            ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
              equipment_json = safe_fetch { fetch_equipment_json }
            end
          rescue => e
            Thread.current[:error] = e
          end

          threads << Thread.new do
            ActiveSupport::Dependencies.interlock.permit_concurrent_loads do
              talents_json = safe_fetch { fetch_talents_json }
            end
          rescue => e
            Thread.current[:error] = e
          end

          threads.each(&:join)

          threads.each do |thr|
            raise thr[:error] if thr[:error]
          end

          [ equipment_json, talents_json ]
        end
        # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

        def handle_blizzard_error(error)
          if error.message.include?("404")
            logger.warn("[SyncCharacterService] 404 → profile private or deleted")
          else
            logger.error("[SyncCharacterService] Error fetching profile: #{error.message}")
          end
        end

        def latest_entries_per_bracket
          PvpLeaderboardEntry
            .joins(:pvp_leaderboard)
            .where(character_id: character.id)
            .select("DISTINCT ON (pvp_leaderboards.bracket) pvp_leaderboard_entries.*")
            .order(
              "pvp_leaderboards.bracket, pvp_leaderboard_entries.snapshot_at DESC, " \
              "pvp_leaderboard_entries.id DESC"
            )
        end

        def logger
          Rails.logger
        end
    end
  end
end
