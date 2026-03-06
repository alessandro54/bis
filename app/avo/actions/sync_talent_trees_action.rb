class Avo::Actions::SyncTalentTreesAction < Avo::BaseAction
  self.name = "Sync Talent Trees"
  self.standalone = true
  self.visible = -> { view.index? }

  def fields
    field :force, as: :boolean, default: false,
      help: "Force re-sync all talents (positions, icons, descriptions)"
  end

  def handle(fields:, **)
    force = fields[:force] || false
    SyncTalentTreesJob.perform_later(force: force)
    succeed("SyncTalentTreesJob enqueued#{force ? ' (forced)' : ''}.")
  end
end
