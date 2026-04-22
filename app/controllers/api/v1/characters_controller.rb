class Api::V1::CharactersController < Api::V1::BaseController
  def index
    characters = Character.first(10)

    render json: characters
  end

  def show
    character = Character.find_by(
      "LOWER(region) = ? AND LOWER(realm) = ? AND LOWER(name) = ?",
      params[:region].downcase, params[:realm].downcase, params[:name].downcase
    )
    return render json: { error: "Not found" }, status: :not_found unless character

    pvp_entries     = season_pvp_entries(character)
    primary_spec_id = pvp_entries.max_by(&:rating)&.spec_id

    render json: Characters::ShowSerializer.new(character, pvp_entries:, primary_spec_id:).call
  end

  private

    def season_pvp_entries(character)
      character.pvp_leaderboard_entries
        .joins(:pvp_leaderboard)
        .where(pvp_leaderboards: { pvp_season_id: current_season.id })
        .select("pvp_leaderboard_entries.rating", "pvp_leaderboard_entries.wins",
                "pvp_leaderboard_entries.losses", "pvp_leaderboard_entries.rank",
                "pvp_leaderboard_entries.spec_id", "pvp_leaderboards.bracket",
                "pvp_leaderboards.region")
    end
end
