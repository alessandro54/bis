class SyncTalentTreesJob < ApplicationJob
  queue_as :default

  def perform(region: "us", force: false)
    result = Blizzard::Data::Talents::SyncTreeService.call(region:, force:)

    if result.success?
      ctx = result.context
      Rails.logger.info(
        "[SyncTalentTreesJob] Done — talents: #{ctx[:talents]}, edges: #{ctx[:edges]}"
      )
    else
      Rails.logger.error("[SyncTalentTreesJob] Failed: #{result.error}")
    end
  end
end
