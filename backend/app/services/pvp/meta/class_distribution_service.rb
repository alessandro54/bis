# frozen_string_literal: true

module Pvp
  module Meta
    class ClassDistributionService
      # --- Reliability priors ---
      WINRATE_PRIOR_GAMES   = 5_000.0
      WINRATE_PRIOR_WINRATE = 0.5

      RATING_PRIOR_ENTRIES  = 80.0

      # --- Power composition (role-agnostic) ---
      POWER_RATING_WEIGHT   = 0.75
      POWER_WINRATE_WEIGHT  = 0.25

      # --- Meta composition (Power + Presence) ---
      # Same calculus for all roles, but weights are calibrated per role.
      # Healers: presence matters more (ladder-defining picks like Disc).
      ROLE_META_WEIGHTS = {
        dps:    { power: 1.00, presence: 0.00 },
        healer: { power: 0.65, presence: 0.35 },
        tank:   { power: 0.75, presence: 0.25 }
      }.freeze

      def initialize(season:, bracket:, region:, role: nil)
        @season  = season
        @bracket = bracket
        @region  = region
        @role    = role&.to_sym
      end

      def call
        grouped_stats = aggregated_stats
        return [] if grouped_stats.empty?

        global_avg_rating = base_scope.average(:rating).to_f

        rows = grouped_stats.filter_map do |stat|
          build_row(stat, global_avg_rating)
        end

        return [] if rows.empty?

        normalize_and_score(rows).sort_by { |row| -row[:meta_score] }
      end

      private

        attr_reader :season, :bracket, :region, :role

        Stat = Struct.new(
          :spec_id,
          :entry_count,
          :avg_rating,
          :p90_rating,
          :total_wins,
          :total_losses,
          keyword_init: true
        )

        # rubocop:disable Metrics/MethodLength
        def aggregated_stats
          base_scope
            .reorder(nil)
            .group("pvp_leaderboard_entries.spec_id")
            .pluck(
              "pvp_leaderboard_entries.spec_id",
              Arel.sql("COUNT(*) AS entry_count"),
              Arel.sql("AVG(pvp_leaderboard_entries.rating) AS avg_rating"),
              Arel.sql("PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY pvp_leaderboard_entries.rating) AS p90_rating"),
              Arel.sql("SUM(pvp_leaderboard_entries.wins) AS total_wins"),
              Arel.sql("SUM(pvp_leaderboard_entries.losses) AS total_losses")
            ).map do |spec_id, entry_count, avg_rating, p90_rating, total_wins, total_losses|
              Stat.new(
                spec_id:      spec_id,
                entry_count:  entry_count.to_i,
                avg_rating:   avg_rating.to_f,
                p90_rating:   p90_rating.to_f,
                total_wins:   total_wins.to_i,
                total_losses: total_losses.to_i
              )
            end
        end
        # rubocop:enable Metrics/MethodLength

        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        def build_row(stat, global_avg_rating)
          spec_id   = ::Wow::Catalog.normalize_spec_id(stat.spec_id)
          spec_data = ::Wow::Catalog::SPECS[spec_id]
          return nil unless spec_data

          row_role   = spec_data[:role]
          spec_slug  = spec_data[:spec_slug]
          class_slug = spec_data[:class_slug]

          return nil if role && row_role != role

          total_games = stat.total_wins + stat.total_losses

          shrunk_winrate = shrink_winrate(stat.total_wins, total_games)
          shrunk_rating  = shrink_rating(stat.p90_rating, stat.entry_count, global_avg_rating)
          volume_raw     = Math.log10([ total_games, 1 ].max)

          {
            class:          class_slug,
            spec:           spec_slug,
            spec_id:        spec_id,
            role:           row_role,
            count:          stat.entry_count,
            total_games:    total_games,
            total_wins:     stat.total_wins,
            mean_rating:    stat.avg_rating.round(2),
            p90_rating:     stat.p90_rating.round(2),
            shrunk_winrate: shrunk_winrate,
            shrunk_rating:  shrunk_rating,
            volume_raw:     volume_raw
          }
        end
        # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

        def shrink_winrate(total_wins, total_games)
          observed = total_games.positive? ? (total_wins.to_f / total_games) : WINRATE_PRIOR_WINRATE
          numerator   = observed * total_games + WINRATE_PRIOR_WINRATE * WINRATE_PRIOR_GAMES
          denominator = total_games + WINRATE_PRIOR_GAMES
          denominator.zero? ? WINRATE_PRIOR_WINRATE : (numerator / denominator)
        end

        def shrink_rating(observed_rating, entry_count, global_avg_rating)
          numerator   = (observed_rating * entry_count) + (global_avg_rating * RATING_PRIOR_ENTRIES)
          denominator = entry_count + RATING_PRIOR_ENTRIES
          denominator.zero? ? global_avg_rating : (numerator / denominator)
        end

        # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        def normalize_and_score(rows)
          winrate_stats = rows.map { |r| r[:shrunk_winrate] }
          rating_stats  = rows.map { |r| r[:shrunk_rating] }

          total_entries   = rows.sum { |r| r[:count] }
          total_games_all = rows.sum { |r| r[:total_games] }.to_f

          # First pass: compute shares (presence raw)
          rows = rows.map do |row|
            games_share = total_games_all.positive? ? (row[:total_games].to_f / total_games_all) : 0.0
            row.merge(games_share: games_share)
          end

          games_share_stats = rows.map { |r| r[:games_share] }

          # Second pass: score
          rows.map do |row|
            winrate_score  = normalize(row[:shrunk_winrate], winrate_stats)
            rating_score   = normalize(row[:shrunk_rating], rating_stats)

            power_score = (
              rating_score  * POWER_RATING_WEIGHT +
              winrate_score * POWER_WINRATE_WEIGHT
            )

            presence_score = normalize(row[:games_share], games_share_stats)

            vol_factor = volume_factor_from_log_games(row[:volume_raw], row[:role])

            weights = meta_weights_for(row[:role])
            base_meta = (
              power_score    * weights[:power] +
              presence_score * weights[:presence]
            )

            meta_score   = (base_meta * vol_factor).round(4)
            hidden_score = (power_score * (1.0 - vol_factor)).round(4)

            row.merge(
              winrate_score:  winrate_score,
              rating_score:   rating_score,
              power_score:    power_score.round(4),
              presence_score: presence_score.round(4),
              volume_factor:  vol_factor.round(4),
              meta_score:     meta_score,
              hidden_score:   hidden_score,
              games_share:    row[:games_share].round(6),
              percentage:     total_entries.positive? ? ((row[:count].to_f / total_entries) * 100).round(2) : 0.0
            )
          end
        end
        # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

        def meta_weights_for(row_role)
          ROLE_META_WEIGHTS.fetch(row_role.to_sym) { ROLE_META_WEIGHTS[:dps] }
        end

        def normalize(value, values)
          min = values.min
          max = values.max
          return 0.5 if max == min

          (value - min) / (max - min)
        end

        def volume_factor_from_log_games(log_games, row_role)
          mid, k, floor = volume_params_for(row_role)
          logistic = 1.0 / (1.0 + Math.exp(-k * (log_games - mid)))
          [ floor, logistic ].max
        end

        def volume_params_for(row_role)
          # Calibrated per role due to different pool sizes & volume skew.
          case row_role.to_sym
          when :healer
            [ 4.30, 4.2, 0.08 ]
          when :tank
            [ 4.05, 3.8, 0.10 ]
          when :dps
            [ 4.18, 4.8, 0.08 ]
          else
            [ 4.18, 4.8, 0.08 ]
          end
        end

        def base_scope
          PvpLeaderboardEntry
            .latest_snapshot_for_bracket(bracket, season_id: season.id)
            .joins(:pvp_leaderboard)
            .where(pvp_leaderboards: { region: region })
            .where.not(
              "pvp_leaderboard_entries.spec_id": nil,
              "pvp_leaderboard_entries.rating":  nil
            )
        end
    end
  end
end
