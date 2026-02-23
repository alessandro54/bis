module Pvp
  module Characters
    class SyncCharacterService < BaseService
      DEFAULT_TTL_HOURS = ENV.fetch("PVP_EQUIPMENT_SNAPSHOT_TTL_HOURS", 24).to_i

      def initialize(character:, locale: "en_US", ttl_hours: DEFAULT_TTL_HOURS, entries: nil)
        @character         = character
        @locale            = locale
        @ttl_hours         = ttl_hours
        @preloaded_entries = entries
      end

      def call
        return success(nil, context: { status: :not_found }) unless character
        return success(nil, context: { status: :skipped_private }) if character.is_private

        # DB read — checked out briefly, then returned to the pool.
        entries = ApplicationRecord.connection_pool.with_connection { latest_entries_per_bracket }
        return success(nil, context: { status: :no_entries }) if entries.empty?

        if recently_synced?
          ApplicationRecord.connection_pool.with_connection { reuse_character_data_for_entries(entries) }
          return success(entries, context: { status: :reused_cache })
        end

        # No connection held here — releases the slot back to the pool so other
        # fibers can do DB work while this one waits on network I/O (~600ms).
        equipment_json, talents_json = fetch_remote_data
        return success(nil, context: { status: :equipment_unavailable }) unless equipment_json
        return success(nil, context: { status: :talents_unavailable }) unless talents_json

        # Re-acquire for all DB writes (equipment, talents, fingerprint, entries).
        ApplicationRecord.connection_pool.with_connection { process_inline(entries, equipment_json, talents_json) }
        success(entries, context: { status: :synced })
      rescue => e
        failure(e)
      end

      private

        attr_reader :character, :locale, :ttl_hours, :preloaded_entries

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
            log_service_failure("Equipment", character, eq_result.error)
            return
          end

          spec_result = Pvp::Entries::ProcessSpecializationService.call(
            character:          character,
            raw_specialization: talents_json,
            locale:             locale
          )

          unless spec_result.success?
            log_service_failure("Specialization", character, spec_result.error)
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

          # Merge character column updates from both services (class_slug, class_id,
          # talent_loadout_code) with last_equipment_snapshot_at into a single
          # update_columns call instead of 3 separate DB round-trips.
          char_attrs = {}
          char_attrs.merge!(spec_result.context[:char_attrs]) if spec_result.context[:char_attrs]
          char_attrs[:last_equipment_snapshot_at] = Time.current

          # rubocop:disable Rails/SkipsModelValidations
          character.update_columns(char_attrs)
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

        # Fetch equipment and talents concurrently via two threads.
        # Async { } does not work here because run_with_threads gives each
        # character its own Ruby thread with no shared Async reactor — each
        # Async block would run sequentially in its own mini-reactor.
        # Plain threads release the GIL during HTTPX network I/O, so both
        # requests truly happen in parallel, halving per-character latency.
        def fetch_remote_data
          equipment_json = nil
          talents_json   = nil

          threads = [
            Thread.new { equipment_json = safe_fetch { fetch_equipment_json } },
            Thread.new { talents_json   = safe_fetch { fetch_talents_json } }
          ]
          threads.each(&:join)

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
          # Use pre-loaded data when available (batch job pre-loads for all
          # characters at once to avoid N+1 queries).
          return preloaded_entries unless preloaded_entries.nil?

          PvpLeaderboardEntry
            .joins(:pvp_leaderboard)
            .where(character_id: character.id)
            .select("DISTINCT ON (pvp_leaderboards.bracket) pvp_leaderboard_entries.*")
            .order(
              "pvp_leaderboards.bracket, pvp_leaderboard_entries.snapshot_at DESC, " \
              "pvp_leaderboard_entries.id DESC"
            )
        end

        def log_service_failure(stage, character, error)
          label = "[SyncCharacterService] #{stage} processing failed " \
                  "for character #{character.id} (#{character.display_name})"

          if error.is_a?(Exception)
            backtrace = error.backtrace&.first(8)&.join("\n  ")
            logger.error("#{label}: #{error.class}: #{error.message}\n  #{backtrace}")
          else
            logger.error("#{label}: #{error}")
          end
        end

        def logger
          Rails.logger
        end
    end
  end
end
