module Pvp
  class SyncCharacterJob < ApplicationJob
    self.enqueue_after_transaction_commit = :always
    queue_as :character_sync

    TTL_HOURS = ENV.fetch("PVP_EQUIPMENT_SNAPSHOT_TTL_HOURS", 24).to_i

    def perform(character_id:, locale: "en_US")
      character = Character.find_by(id: character_id)
      return unless character
      return if character.is_private

      entries = latest_entries_per_bracket(character)
      return if entries.empty?

      snapshot = ::Pvp::Characters::LastEquipmentSnapshotFinderService.call(
        character_id: character.id,
        ttl_hours:    TTL_HOURS
      )

      if snapshot &&
         snapshot.raw_equipment.present? &&
         snapshot.raw_specialization.present? &&
         snapshot.equipment_processed_at.present? &&
         snapshot.specialization_processed_at.present?
        reuse_snapshot_for_entries(snapshot, entries)
        return
      end

      equipment_json = safe_fetch do
        Blizzard::Api::Profile::CharacterEquipmentSummary.fetch(
          region: character.region,
          realm:  character.realm,
          name:   character.name,
          locale: locale
        )
      end
      return unless equipment_json

      talents_json = safe_fetch do
        Blizzard::Api::Profile::CharacterSpecializationSummary.fetch(
          region: character.region,
          realm:  character.realm,
          name:   character.name,
          locale: locale
        )
      end
      return unless talents_json

      apply_fresh_snapshot(entries, equipment_json, talents_json, locale)
    end

    private

      def latest_entries_per_bracket(character)
        # Optimized query with proper indexing
        PvpLeaderboardEntry
          .joins(:pvp_leaderboard)
          .where(character_id: character.id)
          .select("DISTINCT ON (pvp_leaderboards.bracket) pvp_leaderboard_entries.*")
          .order("pvp_leaderboards.bracket, pvp_leaderboard_entries.snapshot_at DESC, pvp_leaderboard_entries.id DESC")
      end

      def reuse_snapshot_for_entries(snapshot, entries)
        Rails.logger.silence do
          entries.each do |entry|
            copy_from_snapshot(snapshot, entry)
          end
        end
      end

      def apply_fresh_snapshot(entries, equipment_json, talents_json, locale)
        Rails.logger.info(
          "[SyncPvpCharacterJob] Fetched fresh snapshot for character #{entries.first.character_id} "\
            "and applying to #{entries.size} latest entries per bracket"
        )

        Rails.logger.silence do
          entries.each do |entry|
            entry.update!(
              raw_equipment:      equipment_json,
              raw_specialization: talents_json
            )

            Pvp::ProcessLeaderboardEntryJob.perform_later(
              entry_id: entry.id,
              locale:   locale
            )
          end
        end
      end

      def copy_from_snapshot(source, target)
        Rails.logger.info(
          "[SyncPvpCharacterJob] Reusing equipment snapshot from entry #{source.id} " \
            "for entry #{target.id}"
        )


        target.update!(
          # raw data
          raw_equipment:               source.raw_equipment,
          raw_specialization:          source.raw_specialization,

          # equipment
          item_level:                  source.item_level,
          tier_set_id:                 source.tier_set_id,
          tier_set_name:               source.tier_set_name,
          tier_set_pieces:             source.tier_set_pieces,
          tier_4p_active:              source.tier_4p_active,
          equipment_processed_at:      source.equipment_processed_at,

          # specialization
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

      def handle_blizzard_error(e)
        if e.message.include?("404")
          Rails.logger.warn("[SyncPvpCharacterJob] 404 → profile private or deleted")
        else
          Rails.logger.error("[SyncPvpCharacterJob] Error: #{e.message}")
        end
      end
  end
end
