class Api::V1::CharactersController < Api::V1::BaseController
  def index
    characters = Character.first(10)

    render json: characters
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  # GET /api/v1/characters/:region/:realm/:name
  def show
    character = Character.find_by(
      "LOWER(region) = ? AND LOWER(realm) = ? AND LOWER(name) = ?",
      params[:region].downcase,
      params[:realm].downcase,
      params[:name].downcase
    )

    return render json: { error: "Not found" }, status: :not_found unless character

    pvp_entries = character.pvp_leaderboard_entries
      .joins(:pvp_leaderboard)
      .where(pvp_leaderboards: { pvp_season_id: current_season.id })
      .select(
        "pvp_leaderboard_entries.rating",
        "pvp_leaderboard_entries.wins",
        "pvp_leaderboard_entries.losses",
        "pvp_leaderboard_entries.rank",
        "pvp_leaderboard_entries.spec_id",
        "pvp_leaderboards.bracket",
        "pvp_leaderboards.region"
      )

    render json: {
      name:        character.name,
      realm:       character.realm,
      region:      character.region.upcase,
      class_slug:  character.class_slug,
      race:        character.race,
      faction:     character.faction,
      avatar_url:  character.avatar_url,
      inset_url:   character.inset_url,
      pvp_entries: pvp_entries.map do |e|
        {
          bracket: e.bracket,
          region:  e.region.upcase,
          rating:  e.rating,
          wins:    e.wins,
          losses:  e.losses,
          rank:    e.rank,
          spec_id: e.spec_id
        }
      end
    }
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
