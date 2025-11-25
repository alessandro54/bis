module Characters
  class SyncCharacterJob < ApplicationJob
    queue_as :default

    def perform(region:, realm:, name:)
      character = Character.find_by(region:, realm:, name:)
      return unless character

      profile = fetch_profile(region: region, realm: realm, name: name)
      return unless profile

      assets = fetch_assets(region: region, realm: realm, name: name)

      character.update!(
        race:         profile.dig("race", "name")&.downcase,
        class_id:     profile.dig("character_class", "id"),
        avatar_url:   asset_value(assets, "avatar"),
        inset_url:    asset_value(assets, "inset"),
        main_raw_url: asset_value(assets, "main-raw")
      )
    rescue Blizzard::Client::Error => e
      handle_blizzard_error(e, character)
    end

    private

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
