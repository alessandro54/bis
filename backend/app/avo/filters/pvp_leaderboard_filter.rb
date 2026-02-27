class Avo::Filters::PvpLeaderboardFilter < Avo::Filters::SelectFilter
  self.name = "Leaderboard"

  def apply(request, query, value)
    query.where(pvp_leaderboard_id: value)
  end

  def options
    PvpLeaderboard.joins(:pvp_season)
      .order("pvp_seasons.blizzard_id DESC", :region, :bracket)
      .pluck(:id, :bracket, :region)
      .map { |id, bracket, region| [ id, "#{region.upcase} – #{bracket}" ] }
      .to_h
  end
end
