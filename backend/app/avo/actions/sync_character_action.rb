class Avo::Actions::SyncCharacterAction < Avo::BaseAction
  self.name = "Sync character"
  self.visible = -> { view.show? }

  def handle(records:, **)
    records.each do |character|
      # rubocop:disable Rails/SkipsModelValidations
      character.update_columns(unavailable_until: nil)
      # rubocop:enable Rails/SkipsModelValidations

      Pvp::SyncCharacterBatchJob
        .set(queue: "character_sync_#{character.region}")
        .perform_later(character_ids: [ character.id ])

      Characters::SyncCharacterJob.perform_later(
        region: character.region,
        realm:  character.realm,
        name:   character.name
      )
    end

    succeed("Sync enqueued for #{records.size} character(s).")
    reload
  end
end
