module Characters
  class SyncCharacterJob < ApplicationJob
    CHARACTER_SYNC_QUEUES = %i[
      character_sync_a
      character_sync_b
      character_sync_c
      character_sync_d
    ].freeze

    queue_as :character_sync

    # Retry on API errors with exponential backoff (network issues, rate limits, etc.)
    retry_on Blizzard::Client::Error, wait: :exponentially_longer, attempts: 3 do |job, error|
      Rails.logger.warn("[Characters::SyncCharacterJob] API error, will retry: #{error.message}")
    end

    def perform(region:, realm:, name:)
      character = Character.find_by(region:, realm:, name:)
      return unless character
      return if character.is_private # Skip private characters early
      return if character.meta_synced?

      profile = fetch_profile(region: region, realm: realm, name: name)
      return unless profile

      assets = fetch_assets(region: region, realm: realm, name: name)

      update_character(character, profile, assets)
    rescue Blizzard::Client::Error => e
      handle_blizzard_error(e, character)
    end

    def self.queue_for(character_id, queues: nil)
      queues ||= CHARACTER_SYNC_QUEUES
      queues[character_id % queues.size]
    end

    private

      def update_character(character, profile, assets)
        character.update!(
          race:           profile.dig("race", "name")&.downcase,
          race_id:        profile.dig("race", "id"),
          class_id:       profile.dig("character_class", "id"),
          avatar_url:     asset_value(assets, "avatar"),
          inset_url:      asset_value(assets, "inset"),
          main_raw_url:   asset_value(assets, "main-raw"),
          meta_synced_at: Time.zone.now
        )
      end
      def fetch_profile(region:, realm:, name:)
        profile = Blizzard::Api::Profile::CharacterProfileSummary.fetch(
          region: region,
          realm:  realm,
          name:   name
        )

        return nil unless profile.key?("id")

        profile
      end

      def fetch_assets(region:, realm:, name:)
        media = Blizzard::Api::Profile::CharacterMediaSummary.fetch(
          region: region,
          realm:  realm,
          name:   name
        )

        media["assets"] || []
      end

      def asset_value(assets, key)
        asset = assets.find { |item| item["key"] == key }
        asset&.dig("value")
      end

      def handle_blizzard_error(error, character)
        if error.message.include?("404")
          character&.update!(is_private: true)
        else
          Rails.logger.error("[Characters::SyncCharacterJob] Error syncing character: #{error.message}")
        end
      end
  end
end
