module Pvp
  module Meta
    # rubocop:disable Metrics/ClassLength
    class TalentAggregationService < BaseService
      include AggregationSql

      TOP_N = ENV.fetch("PVP_META_TOP_N", 1000).to_i

      # Tier thresholds (usage_pct) — raw classification before budget logic
      BIS_THRESHOLD          = 75.0
      SITUATIONAL_THRESHOLD  = 50.0
      COMMON_THRESHOLD       = 35.0

      # Budget per tree type (talent points available)
      TREE_BUDGETS = { "class" => 34, "spec" => 34, "hero" => 10 }.freeze
      HERO_OFF_TREE_THRESHOLD = 30.0

      # Player weight tiers — elite players' choices count more.
      # Elite (3x):       top 15% rating AND winrate > 60%
      # Competitive (2x): top 50% rating OR  winrate > 55%
      # Standard (1x):    everyone else
      ELITE_RATING_PCT       = 0.15
      ELITE_WINRATE          = 60.0
      COMPETITIVE_RATING_PCT = 0.50
      COMPETITIVE_WINRATE    = 55.0

      WEIGHT_ELITE       = 3.0
      WEIGHT_COMPETITIVE = 2.0
      WEIGHT_STANDARD    = 1.0

      def initialize(season:, top_n: TOP_N)
        @season = season
        @top_n  = top_n
      end

      def call
        rows    = execute_query
        rows    = apply_budget_tiers(rows)
        records = build_records(rows)

        if records.any?
          # rubocop:disable Rails/SkipsModelValidations
          PvpMetaTalentPopularity.upsert_all(
            records,
            unique_by:   %i[pvp_season_id bracket spec_id talent_id],
            update_only: %i[talent_type usage_count usage_pct in_top_build top_build_rank tier snapshot_at]
          )
          # rubocop:enable Rails/SkipsModelValidations
        end

        success(records.size, context: { count: records.size })
      rescue => e
        failure(e)
      end

      private

        attr_reader :season, :top_n

        # Override to filter on specialization_processed_at instead of equipment_processed_at
        def top_chars_cte
          <<~SQL
            latest_per_char AS (
              SELECT DISTINCT ON (l.bracket, e.character_id)
                e.character_id,
                l.bracket,
                e.spec_id,
                e.rating,
                e.wins,
                e.losses
              FROM pvp_leaderboard_entries e
              JOIN pvp_leaderboards l ON l.id = e.pvp_leaderboard_id
              WHERE l.pvp_season_id = :season_id
                AND e.spec_id IS NOT NULL
                AND e.specialization_processed_at IS NOT NULL
              ORDER BY l.bracket, e.character_id, e.rating DESC
            ),
            ranked AS (
              SELECT *,
                RANK() OVER (PARTITION BY bracket, spec_id ORDER BY rating DESC) AS rk,
                COUNT(*) OVER (PARTITION BY bracket, spec_id) AS spec_total
              FROM latest_per_char
            ),
            top_chars AS (
              SELECT *,
                CASE
                  WHEN rk <= spec_total * #{ELITE_RATING_PCT}
                    AND wins * 100.0 / NULLIF(wins + losses, 0) > #{ELITE_WINRATE}
                  THEN #{WEIGHT_ELITE}
                  WHEN rk <= spec_total * #{COMPETITIVE_RATING_PCT}
                    OR wins * 100.0 / NULLIF(wins + losses, 0) > #{COMPETITIVE_WINRATE}
                  THEN #{WEIGHT_COMPETITIVE}
                  ELSE #{WEIGHT_STANDARD}
                END AS weight
              FROM ranked WHERE rk <= :top_n
            )
          SQL
        end

        # Builds the top-build CTEs: fingerprint each character's full talent loadout,
        # find the single most common loadout per bracket/spec, expose its talent ids,
        # and compute the modal rank each talent is taken at within that top build.
        def top_build_cte
          <<~SQL
            char_builds AS (
              SELECT
                t.bracket,
                t.spec_id,
                t.character_id,
                t.weight,
                array_agg(ct.talent_id ORDER BY ct.talent_id) AS build
              FROM top_chars t
              JOIN character_talents ct ON ct.character_id = t.character_id AND ct.spec_id = t.spec_id AND ct.rank > 0
              GROUP BY t.bracket, t.spec_id, t.character_id, t.weight
            ),
            build_counts AS (
              SELECT bracket, spec_id, build, SUM(weight) AS cnt
              FROM char_builds
              GROUP BY bracket, spec_id, build
            ),
            best_build AS (
              SELECT DISTINCT ON (bracket, spec_id) bracket, spec_id, build
              FROM build_counts
              ORDER BY bracket, spec_id, cnt DESC
            ),
            top_build_talents AS (
              SELECT bracket, spec_id, unnest(build) AS talent_id
              FROM best_build
            ),
            best_build_chars AS (
              SELECT cb.character_id, cb.bracket, cb.spec_id
              FROM char_builds cb
              JOIN best_build bb
                ON bb.bracket = cb.bracket
               AND bb.spec_id = cb.spec_id
               AND bb.build   = cb.build
            ),
            top_build_talent_ranks AS (
              SELECT
                t.bracket,
                t.spec_id,
                ct.talent_id,
                ct.rank,
                SUM(t.weight) AS cnt
              FROM top_chars t
              JOIN character_talents ct ON ct.character_id = t.character_id AND ct.spec_id = t.spec_id AND ct.rank > 0
              GROUP BY t.bracket, t.spec_id, ct.talent_id, ct.rank
            ),
            top_build_modal_rank AS (
              SELECT DISTINCT ON (bracket, spec_id, talent_id)
                bracket, spec_id, talent_id, rank AS top_build_rank
              FROM top_build_talent_ranks
              ORDER BY bracket, spec_id, talent_id, cnt DESC
            )
          SQL
        end

        # rubocop:disable Metrics/MethodLength
        def execute_query
          sql = <<~SQL
            WITH #{top_chars_cte},
            spec_totals AS (
              SELECT bracket, spec_id, SUM(weight) AS total
              FROM top_chars
              GROUP BY bracket, spec_id
            ),
            talent_usage AS (
              SELECT
                t.bracket,
                t.spec_id,
                ct.talent_id,
                tal.talent_type,
                COALESCE(tsa.default_points, 0) AS default_points,
                SUM(t.weight)::int                              AS usage_count,
                ROUND(SUM(t.weight) * 100.0 / st.total, 4)     AS usage_pct,
                NOW()                                   AS snapshot_at
              FROM top_chars t
              JOIN character_talents ct ON ct.character_id = t.character_id AND ct.spec_id = t.spec_id
              JOIN talents tal ON tal.id = ct.talent_id
              LEFT JOIN talent_spec_assignments tsa
                ON tsa.talent_id = ct.talent_id AND tsa.spec_id = t.spec_id
              JOIN spec_totals st
                ON st.bracket = t.bracket AND st.spec_id = t.spec_id
              GROUP BY t.bracket, t.spec_id, ct.talent_id, tal.talent_type, tsa.default_points, st.total
            ),
            #{top_build_cte}
            SELECT
              tu.bracket,
              tu.spec_id,
              tu.talent_id,
              tu.talent_type,
              tu.default_points,
              tu.usage_count,
              tu.usage_pct,
              tu.snapshot_at,
              EXISTS (
                SELECT 1 FROM top_build_talents tbt
                WHERE tbt.bracket = tu.bracket
                  AND tbt.spec_id = tu.spec_id
                  AND tbt.talent_id = tu.talent_id
              ) AS in_top_build,
              COALESCE(tbmr.top_build_rank, 0) AS top_build_rank,
              CASE
                WHEN tu.default_points > 0      THEN 'bis'
                WHEN tu.usage_pct > :bis_pct     THEN 'bis'
                WHEN tu.usage_pct > :sit_pct     THEN 'situational'
                ELSE 'common'
              END AS tier
            FROM talent_usage tu
            LEFT JOIN top_build_modal_rank tbmr
              ON  tbmr.bracket   = tu.bracket
              AND tbmr.spec_id   = tu.spec_id
              AND tbmr.talent_id = tu.talent_id
            ORDER BY tu.bracket, tu.spec_id, tu.talent_type, tu.usage_count DESC
          SQL

          ApplicationRecord.connection.select_all(
            ApplicationRecord.sanitize_sql_array(
              [ sql, {
                season_id: season.id,
                top_n:     top_n,
                bis_pct:   BIS_THRESHOLD,
                sit_pct:   SITUATIONAL_THRESHOLD
              } ]
            )
          )
        end
        # rubocop:enable Metrics/MethodLength

        # ── Budget-aware tier assignment ─────────────────────────────────
        #
        # For each (bracket, spec, talent_type) group:
        #
        #   Hero trees  → selected sub-tree all BiS, off-tree situational/common
        #   Class/Spec  → fill BiS by best efficiency (pct / cost), then situational
        #
        # Prereqs are OR: a node locked by [A, B, C] only needs ONE satisfied.
        # Choice nodes: primary talent gets node tier, alternatives demoted one level.
        #
        def apply_budget_tiers(rows)
          return rows if rows.empty?

          @prereqs = load_prerequisite_graph
          @talent_info = load_talent_info(rows)

          groups = rows.group_by { |r| [ r["bracket"], r["spec_id"], r["talent_type"] ] }

          groups.each do |(_, _, talent_type), group_rows|
            budget = TREE_BUDGETS[talent_type]
            next unless budget

            node_rows = build_node_rows(group_rows)

            if talent_type == "hero"
              assign_hero_tiers(node_rows)
            else
              assign_tree_tiers(node_rows, budget)
            end
          end

          rows
        end

        # ── Node grouping ───────────────────────────────────────────────

        # Groups SQL rows by node_id. Talents on the same node are choice alternatives.
        def build_node_rows(group_rows)
          node_rows = Hash.new { |h, k| h[k] = [] }
          group_rows.each do |r|
            info = @talent_info[r["talent_id"]]
            next unless info&.[](:node_id)

            node_rows[info[:node_id]] << r
          end
          node_rows
        end

        # Per-node cost/usage metadata. Cost = max_rank - default_points (spec-specific).
        def build_node_meta(node_rows)
          node_meta = {}
          node_rows.each do |node_id, node_group|
            primary = primary_talent(node_group)
            info = @talent_info[primary["talent_id"]]
            next unless info

            dp   = primary["default_points"].to_i
            cost = [ info[:max_rank] - dp, 0 ].max
            node_meta[node_id] = { cost: cost, pct: primary["usage_pct"].to_f, free: cost == 0 }
          end
          node_meta
        end

        # The highest-usage talent on a node (the "pick" for choice nodes).
        def primary_talent(node_group)
          node_group.max_by { |r| r["usage_pct"].to_f }
        end

        # ── Class/Spec tree budget fill ─────────────────────────────────

        def assign_tree_tiers(node_rows, budget)
          node_meta = build_node_meta(node_rows)

          bis_node_ids = collect_free_nodes(node_meta)
          bis_spent    = fill_by_efficiency(bis_node_ids, node_meta, budget, SITUATIONAL_THRESHOLD)

          remaining    = budget - bis_spent
          sit_node_ids = Set.new
          fill_by_efficiency(sit_node_ids, node_meta, remaining, COMMON_THRESHOLD, already: bis_node_ids)

          write_tiers(node_rows, bis_node_ids, sit_node_ids)
        end

        # Free nodes (default_points >= max_rank) cost nothing — always BiS.
        def collect_free_nodes(node_meta)
          free = Set.new
          node_meta.each { |nid, m| free.add(nid) if m[:free] }
          free
        end

        # Iteratively pick the candidate with best efficiency = pct / chain_cost.
        # Recalculates each round because shared prereqs change costs.
        # Returns total points spent.
        def fill_by_efficiency(selected, node_meta, budget, threshold, already: Set.new)
          spent = 0
          combined = already | selected

          loop do
            pick = best_efficiency_pick(combined, node_meta, budget - spent, threshold)
            break unless pick

            select_node_with_prereqs(pick[:node_id], selected, node_meta, exclude: already)
            combined = already | selected
            spent += pick[:cost]
          end

          spent
        end

        # Find the unselected node with highest pct/cost ratio that fits in remaining budget.
        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def best_efficiency_pick(selected, node_meta, remaining, threshold)
          best = nil

          node_meta.each do |nid, m|
            next if selected.include?(nid) || m[:pct] < threshold

            cost = cheapest_path_cost(nid, selected, node_meta)
            next if cost > remaining

            eff = cost == 0 ? Float::INFINITY : m[:pct] / cost

            if best.nil? || eff > best[:eff] || (eff == best[:eff] && m[:pct] > best[:pct])
              best = { node_id: nid, cost: cost, eff: eff, pct: m[:pct] }
            end
          end

          best
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        # Write final tiers to rows. Choice node alternatives demoted one level.
        def write_tiers(node_rows, bis_node_ids, sit_node_ids)
          node_rows.each do |node_id, node_group|
            tier = if bis_node_ids.include?(node_id)
              "bis"
            elsif sit_node_ids.include?(node_id)
              "situational"
            else
              "common"
            end

            assign_tier_to_node(node_group, tier)
          end
        end

        # For a single node: primary gets the tier, choice alternatives drop one level.
        # Multi-rank nodes (same talent, multiple ranks) all get the same tier.
        def assign_tier_to_node(node_group, tier)
          if choice_node?(node_group) && tier != "common"
            primary  = primary_talent(node_group)
            alt_tier = tier == "bis" ? "situational" : "common"
            node_group.each { |r| r["tier"] = r.equal?(primary) ? tier : alt_tier }
          else
            node_group.each { |r| r["tier"] = tier }
          end
        end

        # A choice node has multiple talents with different blizzard_ids (real alternatives).
        # Multi-rank nodes have multiple rows but are the same talent at different ranks.
        def choice_node?(node_group)
          return false if node_group.size <= 1

          node_group.map { |r| @talent_info[r["talent_id"]]&.[](:node_id) }.uniq.size == 1 &&
            node_group.map { |r| r["talent_id"] }.uniq.size > 1 &&
            unique_talent_names(node_group) > 1
        end

        def unique_talent_names(node_group)
          @talent_names ||= Translation
            .where(translatable_type: "Talent", key: "name", locale: "en_US")
            .pluck(:translatable_id, :value)
            .to_h
          node_group.map { |r| @talent_names[r["talent_id"]] }.compact.uniq.size
        end

        # ── Prerequisite path finding (OR semantics) ────────────────────
        #
        # A node locked_by [A, B, C] only needs ONE prereq satisfied.
        # We always pick the cheapest path through the tree.

        # Total cost to unlock node_id, following cheapest OR-prereq at each step.
        def cheapest_path_cost(node_id, selected, node_meta, memo = {})
          return 0 if selected.include?(node_id)
          return memo[node_id] if memo.key?(node_id)

          meta     = node_meta[node_id]
          own_cost = (meta && !meta[:free]) ? meta[:cost] : 0

          prereq_ids = relevant_prereqs(node_id, node_meta)

          memo[node_id] = if prereq_ids.empty?
            own_cost
          else
            cheapest_prereq = prereq_ids.map { |pid|
              cheapest_path_cost(pid, selected, node_meta, memo)
            }.min
            own_cost + cheapest_prereq
          end
        end

        # Add node + its cheapest prereq chain to the selected set.
        # Nodes in `exclude` (e.g. already-selected bis nodes) are treated as satisfied
        # but NOT added to `selected`, preventing cross-set contamination.
        def select_node_with_prereqs(node_id, selected, node_meta, exclude: Set.new)
          return if selected.include?(node_id) || exclude.include?(node_id)

          selected.add(node_id)

          prereq_ids = relevant_prereqs(node_id, node_meta)
          return if prereq_ids.empty?
          return if prereq_ids.any? { |pid| selected.include?(pid) || exclude.include?(pid) }

          cheapest = prereq_ids.min_by { |pid| cheapest_path_cost(pid, selected | exclude, node_meta) }
          select_node_with_prereqs(cheapest, selected, node_meta, exclude: exclude)
        end

        # Prereq node_ids that exist in this tree's node_meta.
        def relevant_prereqs(node_id, node_meta)
          (@prereqs[node_id] || []).select { |pid| node_meta.key?(pid) }
        end

        # ── Hero tree logic ─────────────────────────────────────────────
        #
        # Hero talents have 2 sub-trees (connected components). Players pick one.
        # Selected sub-tree (higher avg usage): all BiS, choice alts → situational.
        # Off-tree: all situational if avg >= 30%, otherwise common.

        def assign_hero_tiers(node_rows)
          sub_trees = find_connected_components(node_rows.keys)

          ranked = sub_trees
            .map { |nodes| { nodes: nodes, avg: avg_usage(nodes, node_rows) } }
            .sort_by { |t| -t[:avg] }

          ranked.each_with_index do |tree, idx|
            if idx == 0
              assign_selected_hero_tree(tree[:nodes], node_rows)
            else
              assign_off_hero_tree(tree[:nodes], tree[:avg], node_rows)
            end
          end
        end

        def assign_selected_hero_tree(node_ids, node_rows)
          node_ids.each do |node_id|
            node_group = node_rows[node_id]
            next unless node_group

            assign_tier_to_node(node_group, "bis")
          end
        end

        def assign_off_hero_tree(node_ids, avg, node_rows)
          tier = avg >= HERO_OFF_TREE_THRESHOLD ? "situational" : "common"
          node_ids.each do |node_id|
            node_group = node_rows[node_id]
            next unless node_group

            node_group.each { |r| r["tier"] = tier }
          end
        end

        def avg_usage(node_ids, node_rows)
          pcts = node_ids.flat_map { |nid| (node_rows[nid] || []).map { |r| r["usage_pct"].to_f } }
          pcts.any? ? pcts.sum / pcts.size : 0.0
        end

        # Split node_ids into connected components via undirected prereq edges.
        def find_connected_components(node_ids)
          node_set = node_ids.to_set
          adj = build_undirected_adjacency(node_set)

          visited    = Set.new
          components = []

          node_ids.each do |n|
            next if visited.include?(n)

            component = bfs_component(n, adj, visited)
            components << component
          end

          components
        end

        def build_undirected_adjacency(node_set)
          adj = Hash.new { |h, k| h[k] = Set.new }
          @prereqs.each do |nid, prereq_ids|
            next unless node_set.include?(nid)

            prereq_ids.each do |pid|
              next unless node_set.include?(pid)

              adj[nid].add(pid)
              adj[pid].add(nid)
            end
          end
          adj
        end

        def bfs_component(start, adj, visited)
          component = Set.new
          stack     = [ start ]
          while stack.any?
            cur = stack.pop
            next if component.include?(cur)

            component.add(cur)
            visited.add(cur)
            adj[cur].each { |nb| stack << nb unless component.include?(nb) }
          end
          component
        end

        # ── Data loading ────────────────────────────────────────────────

        def load_prerequisite_graph
          TalentPrerequisite.pluck(:node_id, :prerequisite_node_id)
            .each_with_object(Hash.new { |h, k| h[k] = [] }) do |(node_id, prereq_id), h|
              h[node_id] << prereq_id
            end
        end

        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def load_talent_info(rows)
          talent_ids = rows.map { |r| r["talent_id"] }.uniq
          return {} if talent_ids.empty?

          talents  = Talent.where(id: talent_ids).pluck(:id, :node_id, :max_rank)
          spec_ids = rows.map { |r| r["spec_id"] }.uniq
          defaults = TalentSpecAssignment
            .where(talent_id: talent_ids, spec_id: spec_ids)
            .pluck(:talent_id, :spec_id, :default_points)

          default_map = defaults.each_with_object({}) do |(tid, sid, dp), h|
            h[[ tid, sid ]] = dp
          end

          talents.each_with_object({}) do |(id, node_id, max_rank), h|
            dp = default_map.select { |(tid, _), _| tid == id }.values.max || 0
            h[id] = { node_id: node_id, max_rank: max_rank || 1, default_points: dp }
          end
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        def build_records(rows)
          now = Time.current
          rows.map do |r|
            {
              pvp_season_id:  season.id,
              bracket:        r["bracket"],
              spec_id:        r["spec_id"],
              talent_id:      r["talent_id"],
              talent_type:    r["talent_type"],
              usage_count:    r["usage_count"],
              usage_pct:      r["usage_pct"],
              in_top_build:   r["in_top_build"],
              top_build_rank: r["top_build_rank"].to_i,
              tier:           r["tier"],
              snapshot_at:    r["snapshot_at"] || now,
              created_at:     now,
              updated_at:     now
            }
          end
        end
    end
  end
end
# rubocop:enable Metrics/ClassLength
