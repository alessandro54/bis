module Blizzard
  module Data
    module Talents
      # Fetches talent tree layout from Blizzard's static Game Data API and persists:
      #   - node_id, display_row, display_col, max_rank, spell_id, talent_type on each Talent
      #   - prerequisite edges in TalentPrerequisite
      #   - spec assignments in TalentSpecAssignment
      #
      # Media (icon_url, descriptions) is fetched asynchronously by SyncTalentMediaJob.
      #
      # Run once after a major patch or on-demand:
      #   SyncTalentTreesJob.perform_later
      class SyncTreeService < BaseService # rubocop:disable Metrics/ClassLength
        TALENT_TYPE_PRIORITY = { "class" => 0, "spec" => 1, "hero" => 2 }.freeze

        def initialize(region: "us", locale: "en_US", force: false)
          @region = region
          @force  = force
          @client = Blizzard::Client.new(region: region, locale: locale)
        end

        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def call
          spec_entries     = Array(fetch_index["spec_talent_trees"])
          talent_attrs     = {}
          name_map         = {} # blizzard_id => name (from tree response, locale-aware)
          edges            = Set.new
          # spec_id => { talent_type => Set<blizzard_id> }
          spec_assignments = Hash.new { |h, k| h[k] = Hash.new { |hh, kk| hh[kk] = Set.new } }
          failed_specs     = []

          spec_entries.each do |entry|
            tree_id, spec_id = parse_ids(entry.dig("key", "href"))
            next unless tree_id && spec_id

            tree = fetch_tree(tree_id, spec_id)
            process_tree(tree, talent_attrs, edges, spec_assignments[spec_id], name_map, spec_id: spec_id)
          rescue Blizzard::Client::Error => e
            failed_specs << spec_id
            log_warn("Skipping tree #{tree_id}/#{spec_id}: #{e.message}")
          end

          if force?
            apply_positions(talent_attrs)
            apply_prerequisites(edges) if failed_specs.empty?
          else
            apply_positions_for_incomplete(talent_attrs)
            apply_prerequisites(edges) if TalentPrerequisite.none? && failed_specs.empty?
          end

          apply_talent_types(talent_attrs)
          apply_spec_assignments(spec_assignments, skip_specs: failed_specs)
          save_names_from_tree(name_map)

          # Media (icons, descriptions) only changes on patch day — only fetch on force sync.
          SyncTalentMediaJob.perform_later(region: @region, locale: @client.locale) if force?

          success(nil, context: { talents: talent_attrs.size, edges: edges.size })
        rescue Blizzard::Client::Error, ActiveRecord::ActiveRecordError => e
          failure(e)
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        private

          attr_reader :region, :client

          def force? = @force

          def fetch_index
            client.get("/data/wow/talent-tree/index", namespace: client.static_namespace)
          end

          def fetch_tree(tree_id, spec_id)
            client.get(
              "/data/wow/talent-tree/#{tree_id}/playable-specialization/#{spec_id}",
              namespace: client.static_namespace
            )
          end

          def parse_ids(href)
            return [ nil, nil ] unless href

            m = href.match(%r{/talent-tree/(\d+)/playable-specialization/(\d+)})
            return [ nil, nil ] unless m

            [ m[1].to_i, m[2].to_i ]
          end

          # rubocop:disable Metrics/AbcSize
          def process_tree(tree, talent_attrs, edges, assignments, name_map, spec_id: nil)
            process_nodes(Array(tree["class_talent_nodes"]), "class", talent_attrs, edges, assignments, name_map)
            process_nodes(Array(tree["spec_talent_nodes"]),  "spec",  talent_attrs, edges, assignments, name_map)
            hero_trees = Array(tree["hero_talent_trees"])
            if hero_trees.empty?
              log_warn("Tree response missing hero_talent_trees for spec #{spec_id || '?'} — " \
                       "existing hero TSAs preserved")
            end
            hero_trees.each do |hero|
              # Blizzard's API renamed "nodes" → "hero_talent_nodes" inside each hero tree.
              # Fall back to the old key for backwards compatibility.
              hero_nodes = Array(hero["hero_talent_nodes"]).presence || Array(hero["nodes"])
              if hero_nodes.empty?
                log_warn("Hero tree #{hero['id']} (#{hero['name']}) for spec #{spec_id || '?'} has no nodes")
              end
              process_nodes(hero_nodes, "hero", talent_attrs, edges, assignments, name_map)
            end
          end
          # rubocop:enable Metrics/AbcSize

          # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          def process_nodes(nodes, talent_type, talent_attrs, edges, assignments, name_map)
            # Backwards-compat: accept either Hash<type, Set> or a plain Set (used by legacy specs).
            ids_bucket = assignments.is_a?(Hash) ? assignments[talent_type] : assignments

            nodes.each do |node|
              node_id     = node["id"]
              display_row = node["display_row"]
              display_col = node["display_col"]
              max_rank    = [ Array(node["ranks"]).size, 1 ].max

              talents_from_node(node).each do |blizzard_id, spell_id, name|
                existing_priority = TALENT_TYPE_PRIORITY[talent_attrs.dig(blizzard_id, :talent_type).to_s] || -1
                new_priority      = TALENT_TYPE_PRIORITY[talent_type] || 0

                # Hero always wins — don't overwrite a higher-priority type (e.g. Halo appears
                # in class_talent_nodes for some specs but hero_talent_trees for others).
                if new_priority >= existing_priority
                  talent_attrs[blizzard_id] = {
                    node_id:     node_id,
                    display_row: display_row,
                    display_col: display_col,
                    max_rank:    max_rank,
                    spell_id:    spell_id,
                    talent_type: talent_type
                  }
                end

                name_map[blizzard_id] = name if name.present?
                ids_bucket.add(blizzard_id)
              end

              Array(node["locked_by"]).each do |prereq|
                prereq_id = prereq.is_a?(Hash) ? prereq["id"] : prereq
                edges << [ node_id, prereq_id ] if prereq_id
              end
            end
          end
          # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

          # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          # Returns [[blizzard_id, spell_id, name], ...] for all talents in the node.
          # Handles regular nodes (ranks[].tooltip) and choice nodes (ranks[].choice_of_tooltips).
          def talents_from_node(node)
            Array(node["ranks"]).flat_map do |rank|
              if rank["tooltip"]
                talent   = rank.dig("tooltip", "talent")
                spell_id = rank.dig("tooltip", "spell_tooltip", "spell", "id")
                talent ? [ [ talent["id"], spell_id, talent["name"] ] ] : []
              elsif rank["choice_of_tooltips"]
                rank["choice_of_tooltips"].filter_map do |c|
                  talent   = c["talent"]
                  spell_id = c.dig("spell_tooltip", "spell", "id")
                  [ talent["id"], spell_id, talent["name"] ] if talent
                end
              else
                []
              end
            end.uniq { |blizzard_id, _| blizzard_id }.compact
          end
          # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

          def apply_positions_for_incomplete(talent_attrs)
            return if talent_attrs.empty?

            incomplete_ids = Talent
              .where(blizzard_id: talent_attrs.keys)
              .where("node_id IS NULL OR spell_id IS NULL")
              .pluck(:blizzard_id)

            return if incomplete_ids.empty?

            apply_positions(talent_attrs.slice(*incomplete_ids))
          end

          def apply_talent_types(talent_attrs)
            return if talent_attrs.empty?

            conn   = ApplicationRecord.connection
            id_map = Talent
              .where(blizzard_id: talent_attrs.keys)
              .pluck(:id, :blizzard_id)
              .to_h { |(id, blz)| [ blz, id ] }

            return if id_map.empty?

            values = id_map.map do |blizzard_id, talent_id|
              type = conn.quote(talent_attrs[blizzard_id][:talent_type])
              "(#{talent_id.to_i}, #{type})"
            end.join(", ")

            # Never downgrade hero — hero classification comes from character profile data
            # (raw_specialization["hero_talents"]), which is more authoritative than the
            # static tree API (which keeps gateway talents like Halo in class_talent_nodes).
            conn.execute(<<~SQL)
              UPDATE talents
              SET talent_type = v.talent_type, updated_at = NOW()
              FROM (VALUES #{values}) AS v(id, talent_type)
              WHERE talents.id = v.id
                AND talents.talent_type IS DISTINCT FROM v.talent_type
                AND talents.talent_type != 'hero'
            SQL
          end

          # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
          def apply_positions(talent_attrs)
            return if talent_attrs.empty?

            id_map = Talent
              .where(blizzard_id: talent_attrs.keys)
              .pluck(:id, :blizzard_id)
              .to_h { |(id, blz)| [ blz, id ] }

            return if id_map.empty?

            # Single bulk UPDATE via VALUES — upsert_all can't be used because the
            # INSERT leg would violate blizzard_id NOT NULL.
            conn = ApplicationRecord.connection
            values = id_map.map do |blizzard_id, talent_id|
              a           = talent_attrs[blizzard_id]
              spell_id    = a[:spell_id] ? a[:spell_id].to_i.to_s : "NULL"
              talent_type = conn.quote(a[:talent_type])
              "(#{talent_id.to_i}, #{a[:node_id].to_i}, #{a[:display_row].to_i}, " \
                "#{a[:display_col].to_i}, #{a[:max_rank].to_i}, #{spell_id}, #{talent_type})"
            end.join(", ")

            conn.execute(<<~SQL)
              UPDATE talents
              SET node_id = v.node_id, display_row = v.display_row,
                  display_col = v.display_col, max_rank = v.max_rank,
                  spell_id = v.spell_id, talent_type = v.talent_type,
                  updated_at = NOW()
              FROM (VALUES #{values})
                AS v(id, node_id, display_row, display_col, max_rank, spell_id, talent_type)
              WHERE talents.id = v.id
            SQL
          end
          # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

          def apply_prerequisites(edges)
            return if edges.empty?

            now  = Time.current
            rows = edges
              .map { |(n, p)| { node_id: n, prerequisite_node_id: p, created_at: now, updated_at: now } }
              .uniq { |r| [ r[:node_id], r[:prerequisite_node_id] ] }

            ApplicationRecord.transaction do
              TalentPrerequisite.delete_all
              # rubocop:disable Rails/SkipsModelValidations
              TalentPrerequisite.insert_all!(rows)
              # rubocop:enable Rails/SkipsModelValidations
            end
          end

          # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
          def apply_spec_assignments(spec_assignments, skip_specs: [])
            return if spec_assignments.empty?

            normalized = normalize_spec_assignments(spec_assignments)

            all_blizzard_ids = normalized.values.flat_map { |by_type| by_type.values.flat_map(&:to_a) }.uniq
            id_map = Talent
              .where(blizzard_id: all_blizzard_ids)
              .pluck(:blizzard_id, :id)
              .to_h

            now = Time.current

            # rubocop:disable Rails/SkipsModelValidations
            normalized.each do |spec_id, by_type|
              next if skip_specs.include?(spec_id)
              next if by_type.empty?

              seen_types = by_type.keys
              talent_ids = by_type.values.flat_map(&:to_a).uniq.filter_map { |blz_id| id_map[blz_id] }
              next if talent_ids.empty?

              ApplicationRecord.transaction do
                # Only delete TSAs for talent_types present in this sync. If a tree
                # section (e.g. hero_talent_trees) is missing from the API response,
                # existing assignments for that type are preserved instead of wiped.
                TalentSpecAssignment
                  .where(spec_id: spec_id)
                  .joins(:talent)
                  .where(talents: { talent_type: seen_types })
                  .where.not(talent_id: talent_ids)
                  .delete_all

                rows = talent_ids.map { |tid| { talent_id: tid, spec_id: spec_id, created_at: now, updated_at: now } }
                TalentSpecAssignment.insert_all(rows, unique_by: %i[talent_id spec_id])
              end
            end
            # rubocop:enable Rails/SkipsModelValidations
          end
          # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

          # Accepts the new shape ({ spec_id => { type => Set } }) or legacy
          # shape ({ spec_id => Enumerable<blizzard_id> }) used by older tests.
          # Legacy entries are bucketed under "unknown" so all talent_types get
          # cleaned (mirrors the prior behaviour for those callers).
          def normalize_spec_assignments(spec_assignments)
            spec_assignments.each_with_object({}) do |(spec_id, value), out|
              if value.is_a?(Hash)
                out[spec_id] = value
              else
                out[spec_id] = { "__legacy__" => Set.new(value) }
              end
            end
          end

          def save_names_from_tree(name_map)
            return if name_map.empty?

            Talent.where(blizzard_id: name_map.keys).find_each do |talent|
              name = name_map[talent.blizzard_id]
              talent.set_translation("name", client.locale, name, meta: { source: "blizzard" }) if name.present?
            end
          end
      end
    end
  end
end
