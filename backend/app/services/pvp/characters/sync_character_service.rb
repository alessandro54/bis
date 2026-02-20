module Pvp
  module Characters
    class SyncCharacterService < BaseService
      DEFAULT_TTL_HOURS = ENV.fetch("PVP_EQUIPMENT_SNAPSHOT_TTL_HOURS", 24).to_i

      def initialize(character:, locale: "en_US", ttl_hours: DEFAULT_TTL_HOURS)
        @character = character
        @locale    = locale
        @ttl_hours = ttl_hours
      end

      def call
        return success(nil, context: { status: :not_found }) unless character
        return success(nil, context: { status: :skipped_private }) if character.is_private

        entries = latest_entries_per_bracket
        return success(nil, context: { status: :no_entries }) if entries.empty?

        if recently_synced?
          reuse_character_data_for_entries(entries)
          return success(entries, context: { status: :reused_cache })
        end

        equipment_json, talents_json = fetch_remote_data
        return success(nil, context: { status: :equipment_unavailable }) unless equipment_json
        return success(nil, context: { status: :talents_unavailable }) unless talents_json

        process_inline(entries, equipment_json, talents_json)
        success(entries, context: { status: :synced })
      rescue => e
        failure(e)
      end

      private

        attr_reader :character, :locale, :ttl_hours

        # ------------------------------------------------------------------
        # TTL / reuse
        # ------------------------------------------------------------------

        def recently_synced?
          character.last_equipment_snapshot_at.present? &&
            character.last_equipment_snapshot_at > ttl_hours.hours.ago
        end

        # When character data is still fresh, propagate entry-level metadata
        # (item_level, spec_id, tier_set, hero_tree) from the most recent
        # processed entry without re-fetching from the Blizzard API.
        # Character items are already up-to-date on the character record.
        def reuse_character_data_for_entries(entries)
          entry_ids = entries.map(&:id)
          return if entry_ids.empty?

          source = PvpLeaderboardEntry
            .where(character_id: character.id)
            .where.not(equipment_processed_at: nil, specialization_processed_at: nil)
            .order(equipment_processed_at: :desc)
            .first

          return unless source

          # rubocop:disable Rails/SkipsModelValidations
          PvpLeaderboardEntry.where(id: entry_ids).update_all(
            item_level:                  source.item_level,
            tier_set_id:                 source.tier_set_id,
            tier_set_name:               source.tier_set_name,
            tier_set_pieces:             source.tier_set_pieces,
            tier_4p_active:              source.tier_4p_active,
            equipment_processed_at:      source.equipment_processed_at,
            spec_id:                     source.spec_id,
            hero_talent_tree_name:       source.hero_talent_tree_name,
            hero_talent_tree_id:         source.hero_talent_tree_id,
            specialization_processed_at: source.specialization_processed_at,
            updated_at:                  Time.current
          )
          # rubocop:enable Rails/SkipsModelValidations

          logger.info(
            "[SyncCharacterService] Reused cached data from entry #{source.id} " \
            "for #{entry_ids.size} entries: #{entry_ids.join(', ')}"
          )
        end

        # ------------------------------------------------------------------
        # Inline processing (fresh fetch)
        # ------------------------------------------------------------------

        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        def process_inline(entries, equipment_json, talents_json)
          eq_result = Pvp::Entries::ProcessEquipmentService.call(
            character:     character,
            raw_equipment: equipment_json,
            locale:        locale
          )

          unless eq_result.success?
            logger.error("[SyncCharacterService] Equipment processing failed for character #{character.id}: #{eq_result.error}")
            return
          end

          spec_result = Pvp::Entries::ProcessSpecializationService.call(
            character:          character,
            raw_specialization: talents_json,
            locale:             locale
          )

          unless spec_result.success?
            logger.error("[SyncCharacterService] Specialization processing failed for character #{character.id}: #{spec_result.error}")
            return
          end

          entry_attrs = {}
          entry_attrs.merge!(eq_result.context[:entry_attrs])   if eq_result.context[:entry_attrs]
          entry_attrs.merge!(spec_result.context[:entry_attrs]) if spec_result.context[:entry_attrs]

          if entry_attrs.any?
            # rubocop:disable Rails/SkipsModelValidations
            PvpLeaderboardEntry.where(id: entries.map(&:id)).update_all(
              entry_attrs.merge(updated_at: Time.current)
            )
            # rubocop:enable Rails/SkipsModelValidations
          end

          # rubocop:disable Rails/SkipsModelValidations
          character.update_columns(last_equipment_snapshot_at: Time.current)
          # rubocop:enable Rails/SkipsModelValidations

          logger.info(
            "[SyncCharacterService] Processed character #{character.id} inline, " \
            "updated #{entries.size} entries"
          )
        end
        # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

        # ------------------------------------------------------------------
        # Blizzard API fetch
        # ------------------------------------------------------------------

        def fetch_remote_data
          equipment_json = nil
          talents_json   = nil

          equipment_task = Async { equipment_json = safe_fetch { fetch_equipment_json } }
          talents_task   = Async { talents_json   = safe_fetch { fetch_talents_json } }

          equipment_task.wait
          talents_task.wait

          [ equipment_json, talents_json ]
        end

        def fetch_equipment_json
          Blizzard::Api::Profile::CharacterEquipmentSummary.fetch(
            region: character.region,
            realm:  character.realm,
            name:   character.name,
            locale: region_locale
          )
        end

        def fetch_talents_json
          Blizzard::Api::Profile::CharacterSpecializationSummary.fetch(
            region: character.region,
            realm:  character.realm,
            name:   character.name,
            locale: region_locale
          )
        end

        # Character profile endpoints don't carry translation-sensitive text —
        # use the region's default locale so the API call is always valid
        # regardless of what translation locale was requested.
        def region_locale
          Blizzard::Client.default_locale_for(character.region)
        end

        def safe_fetch
          yield
        rescue Blizzard::Client::Error => e
          handle_blizzard_error(e)
          nil
        end

        def handle_blizzard_error(error)
          if error.message.include?("404")
            logger.warn("[SyncCharacterService] 404 → profile private or deleted")
          elsif error.is_a?(Blizzard::Client::RateLimitedError)
            logger.warn("[SyncCharacterService] Rate limited (429), skipping character")
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
