class Api::V1::Pvp::Meta::TopPlayersController < Api::V1::BaseController
  DEFAULT_REGIONS  = %w[us eu].freeze
  LIMIT            = 10
  MIN_GAMES              = 50
  GRINDER_GAME_THRESHOLD = 200

  # Composite score:
  #   rating
  #   + winrate_bonus    (up to +120 for ≥75% winrate, 0 at 55%)
  #   - grinder_penalty  (up to -200 for sub-55% winrate with many games)
  #
  # Winrate bonus: rewards players ABOVE 55% winrate (not 50%).
  #   55% = neutral, 65% = +48, 75% = +96, 80% = +120.
  #
  # Grinder penalty: scales with (a) how far below 55% winrate, and
  #   (b) how many games beyond GRINDER_GAME_THRESHOLD.
  #   52% with 783 games → penalty ≈ -52 pts.
  #   48% with 600 games → penalty ≈ -42 pts.
  #   A 110-game player below threshold gets no penalty.
  SCORE_SQL = Arel.sql(<<~SQL.squish)
    pvp_leaderboard_entries.rating
    + LEAST(120, GREATEST(0,
        (pvp_leaderboard_entries.wins * 100.0
          / NULLIF(pvp_leaderboard_entries.wins + pvp_leaderboard_entries.losses, 0)
        - 55) * 4.8
      ))
    - LEAST(200, GREATEST(0,
        (55 - pvp_leaderboard_entries.wins * 100.0
          / NULLIF(pvp_leaderboard_entries.wins + pvp_leaderboard_entries.losses, 0)
        ) * 4.0
        * LEAST(1.0, GREATEST(0,
            (pvp_leaderboard_entries.wins + pvp_leaderboard_entries.losses - #{GRINDER_GAME_THRESHOLD})::float
            / #{GRINDER_GAME_THRESHOLD}
          ))
      ))
  SQL

  # GET /api/v1/pvp/meta/top_players
  # Returns top 10 players for a given bracket + spec.
  # When no region is given, merges US and EU results.
  # Only includes players whose equipment was processed for this spec within
  # the current season window — once a player switches specs,
  # equipment_processed_at stops being refreshed for their old-spec entry.
  def index
    regions   = region_params
    cache_key = meta_cache_key("top_players", bracket_param, spec_id_param, regions.join("+"))

    json = meta_cache_fetch(cache_key) do
      rows = query_top_players(regions)

      {
        bracket:     bracket_param,
        spec_id:     spec_id_param,
        regions:     regions,
        players:     serialize_players(rows),
        snapshot_at: rows.first&.snapshot_at
      }
    end

    render json: json
    set_cache_headers
  end

  private

    def bracket_param
      params.require(:bracket)
    end

    def spec_id_param
      params.require(:spec_id).to_i
    end

    def region_params
      if params[:region].present?
        Array(params[:region])
      else
        DEFAULT_REGIONS
      end
    end

    # rubocop:disable Metrics/MethodLength
    def query_top_players(regions)
      base = PvpLeaderboardEntry
        .joins(:pvp_leaderboard, :character)
        .where(
          pvp_leaderboards:        { pvp_season_id: current_season.id, bracket: bracket_param, region: regions },
          pvp_leaderboard_entries: { spec_id: spec_id_param }
        )
        .where.not(equipment_processed_at: nil)
        .where("pvp_leaderboard_entries.equipment_processed_at >= ?", 60.days.ago)
        .order(Arel.sql("(#{SCORE_SQL}) DESC"))
        .limit(LIMIT)
        .select(
          "pvp_leaderboard_entries.rating",
          "pvp_leaderboard_entries.wins",
          "pvp_leaderboard_entries.losses",
          "pvp_leaderboard_entries.rank",
          "pvp_leaderboard_entries.hero_talent_tree_name",
          "pvp_leaderboard_entries.snapshot_at",
          "ROUND((#{SCORE_SQL})::numeric, 1) AS score",
          "characters.name",
          "characters.realm",
          "characters.region",
          "characters.avatar_url",
          "characters.class_slug"
        )

      # If fewer than LIMIT pass the games threshold, fall back without it
      scored = base.where("pvp_leaderboard_entries.wins + pvp_leaderboard_entries.losses >= ?", MIN_GAMES)
      scored.size >= LIMIT ? scored : base
    end
    # rubocop:enable Metrics/MethodLength

    def serialize_players(rows)
      rows.map do |row|
        {
          name:                  row.name,
          realm:                 row.realm,
          region:                row.region,
          rating:                row.rating,
          wins:                  row.wins,
          losses:                row.losses,
          rank:                  row.rank,
          score:                 row.score.to_f,
          avatar_url:            row.avatar_url,
          class_slug:            row.class_slug,
          hero_talent_tree_name: row.hero_talent_tree_name
        }
      end
    end
end
