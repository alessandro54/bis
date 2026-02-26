module Pvp
  module Characters
    class SyncCharacterService < BaseService
      # Carries the result of a single ETag-aware Blizzard API fetch.
      #   json    — parsed response body (nil on 304)
      #   last_modified — Last-Modified header to store on the character
      #   changed — true = 200 (new data), false = 304 (unchanged)
      FetchResult = Struct.new(:json, :last_modified, :changed, keyword_init: true) do
        def changed?   = changed
        def unchanged? = !changed
      end

      def initialize(character:, locale: "en_US", entries: nil,
                     eq_fallback_source: nil, spec_fallback_source: nil)
        @character            = character
        @locale               = locale
        @preloaded_entries    = entries
        @eq_fallback_source   = eq_fallback_source
        @spec_fallback_source = spec_fallback_source
      end

      def call
        return success(nil, context: { status: :not_found }) unless character
        return success(nil, context: { status: :skipped_private }) if character.is_private

        entries = ApplicationRecord.connection_pool.with_connection { latest_entries_per_bracket }
        return success(nil, context: { status: :no_entries }) if entries.empty?

        # If no processed entries exist, the 304 fallback has no source to
        # copy from. Clear Last-Modified so Blizzard returns 200 (full data)
        # instead of 304, ensuring entries get all attrs on first sync or
        # after a data reset.
        ApplicationRecord.connection_pool.with_connection { clear_stale_last_modified! }

        # Always hit Blizzard — the API returns 304 when data is unchanged
        # (cheap), so we don't need a client-side TTL guard. On 304 the
        # existing processed data is propagated to new entries; on 200 fresh
        # data is written.
        eq_fetch, spec_fetch = fetch_remote_data

        if @profile_not_found
          ApplicationRecord.connection_pool.with_connection do
            # rubocop:disable Rails/SkipsModelValidations
            character.update_columns(unavailable_until: UNAVAILABILITY_COOLDOWN.from_now)
            # rubocop:enable Rails/SkipsModelValidations
          end
        end

        return success(nil, context: { status: :equipment_unavailable }) if eq_fetch.nil?
        return success(nil, context: { status: :talents_unavailable })   if spec_fetch.nil?

        ApplicationRecord.connection_pool.with_connection { process_inline(entries, eq_fetch, spec_fetch) }
        success(entries, context: { status: :synced })
      rescue => e
        failure(e)
      end

      private

        attr_reader :character, :locale, :preloaded_entries

        # ------------------------------------------------------------------
        # Inline processing (fresh fetch or 304)
        # ------------------------------------------------------------------

        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        def process_inline(entries, eq_fetch, spec_fetch)
          entry_attrs = {}
          char_attrs  = {}

          # --- Equipment ---
          if eq_fetch.changed?
            eq_result = Pvp::Entries::ProcessEquipmentService.call(
              character:     character,
              raw_equipment: eq_fetch.json,
              locale:        locale
            )

            unless eq_result.success?
              log_service_failure("Equipment", character, eq_result.error)
              return
            end

            entry_attrs.merge!(eq_result.context[:entry_attrs]) if eq_result.context[:entry_attrs]
            char_attrs[:equipment_last_modified] = eq_fetch.last_modified if eq_fetch.last_modified.present?
          else
            # 304: equipment unchanged — propagate attrs from latest processed entry
            entry_attrs.merge!(equipment_entry_attrs_from_latest)
          end

          # --- Specialization ---
          if spec_fetch.changed?
            spec_result = Pvp::Entries::ProcessSpecializationService.call(
              character:          character,
              raw_specialization: spec_fetch.json,
              locale:             locale
            )

            unless spec_result.success?
              log_service_failure("Specialization", character, spec_result.error)
              return
            end

            entry_attrs.merge!(spec_result.context[:entry_attrs]) if spec_result.context[:entry_attrs]
            char_attrs.merge!(spec_result.context[:char_attrs])   if spec_result.context[:char_attrs]
            char_attrs[:talents_last_modified] = spec_fetch.last_modified if spec_fetch.last_modified.present?
          else
            # 304: talents unchanged — propagate attrs from latest processed entry
            entry_attrs.merge!(spec_entry_attrs_from_latest)
          end

          if entry_attrs.any?
            # rubocop:disable Rails/SkipsModelValidations
            PvpLeaderboardEntry.where(id: entries.map(&:id)).update_all(
              entry_attrs.merge(updated_at: Time.current)
            )
            # rubocop:enable Rails/SkipsModelValidations
          end

          char_attrs[:last_equipment_snapshot_at] = Time.current
          char_attrs[:unavailable_until]          = nil

          # rubocop:disable Rails/SkipsModelValidations
          character.update_columns(char_attrs)
          # rubocop:enable Rails/SkipsModelValidations

          logger.info(
            "[SyncCharacterService] Processed character #{character.id} inline, " \
            "updated #{entries.size} entries " \
            "(equipment: #{eq_fetch.changed? ? 'changed' : '304'}, " \
            "talents: #{spec_fetch.changed? ? 'changed' : '304'})"
          )
        end
        # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

        # ------------------------------------------------------------------
        # 304 fallback: copy entry-level attrs from latest processed entry
        # ------------------------------------------------------------------

        def equipment_entry_attrs_from_latest
          source = @eq_fallback_source || PvpLeaderboardEntry
            .where(character_id: character.id)
            .where.not(equipment_processed_at: nil)
            .order(equipment_processed_at: :desc)
            .first
          return {} unless source

          {
            item_level:             source.item_level,
            tier_set_id:            source.tier_set_id,
            tier_set_name:          source.tier_set_name,
            tier_set_pieces:        source.tier_set_pieces,
            tier_4p_active:         source.tier_4p_active,
            equipment_processed_at: source.equipment_processed_at
          }
        end

        def spec_entry_attrs_from_latest
          source = @spec_fallback_source || PvpLeaderboardEntry
            .where(character_id: character.id)
            .where.not(specialization_processed_at: nil)
            .order(specialization_processed_at: :desc)
            .first
          return {} unless source

          {
            spec_id:                     source.spec_id,
            hero_talent_tree_id:         source.hero_talent_tree_id,
            hero_talent_tree_name:       source.hero_talent_tree_name,
            specialization_processed_at: source.specialization_processed_at
          }
        end

        # ------------------------------------------------------------------
        # Blizzard API fetch (two parallel threads)
        # ------------------------------------------------------------------

        def fetch_remote_data
          eq_fetch   = nil
          spec_fetch = nil

          threads = [
            Thread.new { eq_fetch   = safe_fetch { fetch_equipment_with_last_modified } },
            Thread.new { spec_fetch = safe_fetch { fetch_talents_with_last_modified } }
          ]
          threads.each(&:join)

          [ eq_fetch, spec_fetch ]
        end

        def fetch_equipment_with_last_modified
          json, last_modified_str, changed = Blizzard::Api::Profile::CharacterEquipmentSummary.fetch_with_last_modified(
            region:        character.region,
            realm:         character.realm,
            name:          character.name,
            locale:        region_locale,
            last_modified: character.equipment_last_modified&.httpdate
          )
          FetchResult.new(json: json, last_modified: parse_last_modified(last_modified_str), changed: changed)
        end

        def fetch_talents_with_last_modified
          json, last_modified_str, changed = Blizzard::Api::Profile::CharacterSpecializationSummary.fetch_with_last_modified(
            region:        character.region,
            realm:         character.realm,
            name:          character.name,
            locale:        region_locale,
            last_modified: character.talents_last_modified&.httpdate
          )
          FetchResult.new(json: json, last_modified: parse_last_modified(last_modified_str), changed: changed)
        end

        def parse_last_modified(value)
          return nil if value.blank?

          Time.parse(value).utc
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

        UNAVAILABILITY_COOLDOWN = 2.weeks

        def handle_blizzard_error(error)
          if error.is_a?(Blizzard::Client::NotFoundError)
            logger.warn(
              "[SyncCharacterService] 404 for character #{character.id} — " \
              "profile deleted or transferred, cooling down for 2 weeks"
            )
            @profile_not_found = true
          elsif error.is_a?(Blizzard::Client::RateLimitedError)
            logger.warn("[SyncCharacterService] Rate limited (429), skipping character")
          else
            logger.error("[SyncCharacterService] Error fetching profile: #{error.message}")
          end
        end

        # When no processed entries exist for a character (e.g. first sync
        # or after manual data deletion), clear Last-Modified timestamps so
        # Blizzard returns 200 instead of 304.  Without this, a 304 fallback
        # would find no source entry and leave new entries unprocessed.
        def clear_stale_last_modified!
          needs_eq_clear   = character.equipment_last_modified.present? &&
                             !@eq_fallback_source &&
                             !PvpLeaderboardEntry.where(character_id: character.id)
                                                 .where.not(equipment_processed_at: nil).exists?

          needs_spec_clear = character.talents_last_modified.present? &&
                             !@spec_fallback_source &&
                             !PvpLeaderboardEntry.where(character_id: character.id)
                                                 .where.not(specialization_processed_at: nil).exists?

          attrs = {}
          attrs[:equipment_last_modified] = nil if needs_eq_clear
          attrs[:talents_last_modified]   = nil if needs_spec_clear

          if attrs.any?
            # rubocop:disable Rails/SkipsModelValidations
            character.update_columns(attrs)
            # rubocop:enable Rails/SkipsModelValidations
            logger.info(
              "[SyncCharacterService] Cleared stale Last-Modified for character #{character.id} " \
              "(#{attrs.keys.join(', ')}) — no processed entries to fall back on"
            )
          end
        end

        def latest_entries_per_bracket
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
