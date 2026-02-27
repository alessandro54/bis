module Pvp
  class SyncCharacterBatchJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :character_sync_us # overridden per-region via .set(queue:) when enqueued

    CONCURRENCY = ENV.fetch("PVP_SYNC_CONCURRENCY", 15).to_i
    # Threads dedicated to character_sync queues — NOT the total worker thread
    # count. In production each region queue has its own worker (default 8
    # threads). Set PVP_SYNC_THREADS to match that worker's thread count so
    # safe_concurrency divides the pool correctly.
    THREADS     = ENV.fetch("PVP_SYNC_THREADS", 8).to_i

    retry_on Blizzard::Client::Error, wait: :polynomially_longer, attempts: 3 do |_job, error|
      Rails.logger.warn("[SyncCharacterBatchJob] API error, will retry: #{error.message}")
    end

    # rubocop:disable Metrics/AbcSize
    def perform(character_ids:, locale: "en_US", sync_cycle_id: nil)
      @sync_cycle_id = sync_cycle_id

      ids = Array(character_ids).compact
      return if ids.empty?

      # No TTL filter here — the service decides whether to fetch from
      # Blizzard (TTL expired) or reuse cached data (recently synced).
      # Either way, new entries always get processed.
      characters_by_id = Character
        .where(id: ids)
        .where(is_private: false)
        .where("unavailable_until IS NULL OR unavailable_until < ?", Time.current)
        .index_by(&:id)

      enqueue_meta_sync_for_stale(ids)

      # Characters on cooldown still need their new entries populated
      # with cached data from the latest processed entry.
      skipped_ids = ids - characters_by_id.keys
      propagate_cached_entry_data(skipped_ids) if skipped_ids.any?

      return if characters_by_id.empty?

      outcome = BatchOutcome.new

      # Characters are fetched from the Blizzard API and processed inline —
      # equipment and talents are written directly to character_items /
      # character_talents without an intermediate blob storage step.
      process_characters_concurrently(characters_by_id.values, locale, outcome)

      Rails.logger.info(outcome.summary_message(job_label: "SyncCharacterBatchJob"))
      Pvp::SyncLogger.batch_complete(outcome: outcome)
      outcome.raise_if_total_failure!(job_label: "SyncCharacterBatchJob")
    ensure
      track_sync_cycle_completion
    end
    # rubocop:enable Metrics/AbcSize

    private

      def process_characters_concurrently(characters, locale, outcome)
        return if characters.empty?

        character_ids = characters.map(&:id)

        # Three bulk queries replace up to 3N per-character queries:
        #   1. Latest entry per bracket (for entries passed to service)
        #   2. Latest processed entry for equipment 304 fallback attrs
        #   3. Latest processed entry for spec 304 fallback attrs
        entries_by_character_id      = batch_load_entries(character_ids)
        eq_fallbacks_by_character_id = batch_load_eq_fallbacks(character_ids)
        sp_fallbacks_by_character_id = batch_load_spec_fallbacks(character_ids)

        concurrency = safe_concurrency(CONCURRENCY, characters.size, threads: THREADS)

        run_with_threads(characters, concurrency: concurrency) do |character|
          sync_one(
            character:            character,
            locale:               locale,
            outcome:              outcome,
            entries:              entries_by_character_id[character.id] || [],
            eq_fallback_source:   eq_fallbacks_by_character_id[character.id],
            spec_fallback_source: sp_fallbacks_by_character_id[character.id]
          )
        end
      end

      # Latest entry with equipment attrs set — used when Blizzard returns 304
      # (unchanged) so we can propagate existing attrs without re-processing.
      def batch_load_eq_fallbacks(character_ids)
        PvpLeaderboardEntry
          .where(character_id: character_ids)
          .where.not(equipment_processed_at: nil)
          .select("DISTINCT ON (character_id) pvp_leaderboard_entries.*")
          .order("character_id, equipment_processed_at DESC")
          .index_by(&:character_id)
      end

      # Same for specialization attrs.
      def batch_load_spec_fallbacks(character_ids)
        PvpLeaderboardEntry
          .where(character_id: character_ids)
          .where.not(specialization_processed_at: nil)
          .select("DISTINCT ON (character_id) pvp_leaderboard_entries.*")
          .order("character_id, specialization_processed_at DESC")
          .index_by(&:character_id)
      end

      # Single DISTINCT ON query for all characters; groups results by character_id.
      def batch_load_entries(character_ids)
        PvpLeaderboardEntry
          .joins(:pvp_leaderboard)
          .where(character_id: character_ids)
          .select(
            "DISTINCT ON (pvp_leaderboard_entries.character_id, pvp_leaderboards.bracket) " \
            "pvp_leaderboard_entries.*"
          )
          .order(
            "pvp_leaderboard_entries.character_id, pvp_leaderboards.bracket, " \
            "pvp_leaderboard_entries.snapshot_at DESC, pvp_leaderboard_entries.id DESC"
          )
          .group_by(&:character_id)
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      def sync_one(character:, locale:, outcome:, entries: nil, eq_fallback_source: nil, spec_fallback_source: nil)
        return unless character

        result = Pvp::Characters::SyncCharacterService.call(
          character:            character,
          locale:               locale,
          entries:              entries,
          eq_fallback_source:   eq_fallback_source,
          spec_fallback_source: spec_fallback_source
        )

        if result.success?
          outcome.record_success(id: character.id, status: result.context[:status])
        else
          outcome.record_failure(id: character.id, status: :failed, error: result.error.to_s)
        end
      rescue Blizzard::Client::RateLimitedError => e
        Rails.logger.warn(
          "[SyncCharacterBatchJob] Rate limited for character #{character&.id}: #{e.message}"
        )
        outcome.record_failure(id: character&.id, status: :rate_limited, error: e.message)
      rescue Blizzard::Client::Error => e
        Rails.logger.warn(
          "[SyncCharacterBatchJob] API error for character #{character&.id}: #{e.message}"
        )
        outcome.record_failure(id: character&.id, status: :api_error, error: e.message)
      rescue => e
        Rails.logger.error(
          "[SyncCharacterBatchJob] Unexpected error for character #{character&.id}: #{e.class}: #{e.message}"
        )
        outcome.record_failure(id: character&.id, status: :unexpected_error, error: "#{e.class}: #{e.message}")
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      # Bulk-copy equipment & spec attrs from the latest processed entry to
      # any unprocessed entries for characters that were skipped (cooldown or
      # TTL). A single UPDATE … FROM keeps this to one round-trip.
      # rubocop:disable Metrics/MethodLength
      def propagate_cached_entry_data(skipped_ids)
        return if skipped_ids.empty?

        sql = <<~SQL.squish
          UPDATE pvp_leaderboard_entries AS target
          SET
            item_level                  = source.item_level,
            tier_set_id                 = source.tier_set_id,
            tier_set_name               = source.tier_set_name,
            tier_set_pieces             = source.tier_set_pieces,
            tier_4p_active              = source.tier_4p_active,
            equipment_processed_at      = source.equipment_processed_at,
            spec_id                     = source.spec_id,
            hero_talent_tree_name       = source.hero_talent_tree_name,
            hero_talent_tree_id         = source.hero_talent_tree_id,
            specialization_processed_at = source.specialization_processed_at,
            updated_at                  = NOW()
          FROM (
            SELECT DISTINCT ON (character_id)
              character_id, item_level, tier_set_id, tier_set_name, tier_set_pieces,
              tier_4p_active, equipment_processed_at, spec_id, hero_talent_tree_name,
              hero_talent_tree_id, specialization_processed_at
            FROM pvp_leaderboard_entries
            WHERE character_id IN (?)
              AND equipment_processed_at IS NOT NULL
            ORDER BY character_id, equipment_processed_at DESC
          ) AS source
          WHERE target.character_id = source.character_id
            AND target.equipment_processed_at IS NULL
        SQL

        sanitized = ApplicationRecord.sanitize_sql_array([ sql, skipped_ids ])
        count = ApplicationRecord.connection.exec_update(sanitized, "PropagateCache")

        return unless count > 0

        Rails.logger.info(
          "[SyncCharacterBatchJob] Propagated cached data to #{count} entries " \
          "for skipped characters (cooldown/TTL)"
        )
      end
      # rubocop:enable Metrics/MethodLength

      def enqueue_meta_sync_for_stale(character_ids)
        stale_ids = Character
          .where(id: character_ids)
          .where(is_private: false)
          .where("meta_synced_at IS NULL OR meta_synced_at < ?", 1.week.ago)
          .pluck(:id)

        return if stale_ids.empty?

        ::Characters::SyncCharacterMetaBatchJob.perform_later(character_ids: stale_ids)
        Rails.logger.info("[SyncCharacterBatchJob] Enqueued meta batch for #{stale_ids.size} stale characters")
      end

      def track_sync_cycle_completion
        return unless @sync_cycle_id

        cycle = PvpSyncCycle.find_by(id: @sync_cycle_id)
        return unless cycle

        cycle.increment_completed_character_batches!

        if cycle.all_character_batches_done?
          cycle.update!(status: :completed)
          Pvp::BuildAggregationsJob.perform_later(
            pvp_season_id:    cycle.pvp_season_id,
            sync_cycle_id:    cycle.id,
            cycle_started_at: cycle.snapshot_at.iso8601
          )
        end
      rescue => e
        Rails.logger.error(
          "[SyncCharacterBatchJob] Failed to track sync cycle #{@sync_cycle_id}: #{e.message}"
        )
      end
  end
end
