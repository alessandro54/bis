class Avo::Actions::SyncLeaderboardsAction < Avo::BaseAction
  self.name = "Sync Current Season Leaderboards"
  self.standalone = true
  self.visible = -> { view.index? }

  def handle(**)
    Pvp::SyncCurrentSeasonLeaderboardsJob.perform_later
    succeed("SyncCurrentSeasonLeaderboardsJob enqueued.")
  end
end
