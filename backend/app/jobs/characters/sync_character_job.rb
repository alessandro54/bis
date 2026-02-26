module Characters
  class SyncCharacterJob < ApplicationJob
    UNAVAILABILITY_COOLDOWN = 2.weeks

    queue_as :character_sync

    # 404s mean the character is private/deleted — no point retrying
    discard_on Blizzard::Client::NotFoundError do |job, error|
      character = Character.find_by(region: job.arguments.first[:region],
                                    realm:  job.arguments.first[:realm],
                                    name:   job.arguments.first[:name])
      character&.update_columns(is_private: true) # rubocop:disable Rails/SkipsModelValidations
    end

    # Retry transient API errors; on exhaustion, cool down the character
    retry_on Blizzard::Client::Error, wait: :polynomially_longer, attempts: 3 do |job, error|
      Rails.logger.warn("[Characters::SyncCharacterJob] Retries exhausted: #{error.message}")
      character = Character.find_by(region: job.arguments.first[:region],
                                    realm:  job.arguments.first[:realm],
                                    name:   job.arguments.first[:name])
      # rubocop:disable Rails/SkipsModelValidations
      character&.update_columns(unavailable_until: UNAVAILABILITY_COOLDOWN.from_now)
      # rubocop:enable Rails/SkipsModelValidations
    end

    def perform(region:, realm:, name:)
      character = Character.find_by(region:, realm:, name:)
      return unless character
      return if character.is_private
      return if character.meta_synced?

      profile = fetch_profile(region: region, realm: realm, name: name)

      unless profile
        Rails.logger.info("[Characters::SyncCharacterJob] No profile for #{name}-#{realm} (#{region}), cooling down")
        # rubocop:disable Rails/SkipsModelValidations
        character.update_columns(unavailable_until: UNAVAILABILITY_COOLDOWN.from_now)
        # rubocop:enable Rails/SkipsModelValidations
        return
      end

      assets = fetch_assets(region: region, realm: realm, name: name)

      update_character(character, profile, assets)
    end

    private

      def update_character(character, profile, assets)
        was_unavailable = character.unavailable_until.present?

        character.update_columns( # rubocop:disable Rails/SkipsModelValidations
          race:              profile.dig("race", "name")&.downcase,
          race_id:           profile.dig("race", "id"),
          class_id:          profile.dig("character_class", "id"),
          avatar_url:        asset_value(assets, "avatar"),
          inset_url:         asset_value(assets, "inset"),
          main_raw_url:      asset_value(assets, "main-raw"),
          meta_synced_at:    Time.zone.now,
          unavailable_until: nil,
          updated_at:        Time.current
        )

        if was_unavailable
          Pvp::SyncCharacterBatchJob
            .set(queue: "character_sync_#{character.region}")
            .perform_later(character_ids: [ character.id ])
        end
      end

      def fetch_profile(region:, realm:, name:)
        profile = Blizzard::Api::Profile::CharacterProfileSummary.fetch(
          region: region,
          realm:  realm,
          name:   name,
          locale: Blizzard::Client.default_locale_for(region)
        )

        return nil unless profile.key?("id")

        profile
      end

      def fetch_assets(region:, realm:, name:)
        media = Blizzard::Api::Profile::CharacterMediaSummary.fetch(
          region: region,
          realm:  realm,
          name:   name,
          locale: Blizzard::Client.default_locale_for(region)
        )

        media["assets"] || []
      end

      def asset_value(assets, key)
        asset = assets.find { |item| item["key"] == key }
        asset&.dig("value")
      end
  end
end
