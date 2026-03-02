module Blizzard
  module Data
    module Talents
      # Fetches talent tree layout from Blizzard's static Game Data API and persists:
      #   - node_id, display_row, display_col, max_rank, spell_id on each Talent
      #   - prerequisite edges in TalentPrerequisite
      #   - icon_url (via /data/wow/media/spell/{spell_id}) for talents missing one
      #
      # Run once after a major patch or on-demand:
      #   SyncTalentTreesJob.perform_later
      # rubocop:disable Metrics/ClassLength
      class SyncTreeService < BaseService
        def initialize(region: "us")
          @region = region
          @client = Blizzard::Client.new(region: region, locale: "en_US")
        end

        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        def call
          spec_entries     = Array(fetch_index["spec_talent_trees"])
          talent_attrs     = {}
          edges            = Set.new
          spec_assignments = Hash.new { |h, k| h[k] = Set.new } # spec_id => Set<blizzard_id>

          spec_entries.each do |entry|
            tree_id, spec_id = parse_ids(entry.dig("key", "href"))
            next unless tree_id && spec_id

            tree = fetch_tree(tree_id, spec_id)
            process_tree(tree, talent_attrs, edges, spec_assignments[spec_id])
          rescue Blizzard::Client::Error => e
            Rails.logger.warn(
              "[SyncTreeService] Skipping tree #{tree_id}/#{spec_id}: #{e.message}"
            )
          end

          apply_positions(talent_attrs)
          apply_prerequisites(edges)
          apply_spec_assignments(spec_assignments)
          fetch_missing_media

          success(nil, context: { talents: talent_attrs.size, edges: edges.size })
        rescue => e
          failure(e)
        end
        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        private

          attr_reader :region, :client

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

          def process_tree(tree, talent_attrs, edges, spec_blizzard_ids)
            process_nodes(Array(tree["class_talent_nodes"]), talent_attrs, edges, spec_blizzard_ids)
            process_nodes(Array(tree["spec_talent_nodes"]),  talent_attrs, edges, spec_blizzard_ids)
            Array(tree["hero_talent_trees"]).each do |hero|
              process_nodes(Array(hero["nodes"]), talent_attrs, edges, spec_blizzard_ids)
            end
          end

          # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
          def process_nodes(nodes, talent_attrs, edges, spec_blizzard_ids)
            nodes.each do |node|
              node_id     = node["id"]
              display_row = node["display_row"]
              display_col = node["display_col"]
              max_rank    = [ Array(node["ranks"]).size, 1 ].max

              talents_from_node(node).each do |blizzard_id, spell_id|
                talent_attrs[blizzard_id] = {
                  node_id:     node_id,
                  display_row: display_row,
                  display_col: display_col,
                  max_rank:    max_rank,
                  spell_id:    spell_id
                }
                spec_blizzard_ids.add(blizzard_id)
              end

              Array(node["locked_by"]).each do |prereq|
                prereq_id = prereq.is_a?(Hash) ? prereq["id"] : prereq
                edges << [ node_id, prereq_id ] if prereq_id
              end
            end
          end
          # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

          # Returns [[blizzard_id, spell_id], ...] for all talents in the node.
          # Handles regular nodes (ranks[].tooltip) and choice nodes (ranks[].choice_of_tooltips).
          def talents_from_node(node)
            Array(node["ranks"]).flat_map do |rank|
              if rank["tooltip"]
                talent   = rank.dig("tooltip", "talent")
                spell_id = rank.dig("tooltip", "spell_tooltip", "spell", "id")
                talent ? [ [ talent["id"], spell_id ] ] : []
              elsif rank["choice_of_tooltips"]
                rank["choice_of_tooltips"].filter_map do |c|
                  talent   = c["talent"]
                  spell_id = c.dig("spell_tooltip", "spell", "id")
                  [ talent["id"], spell_id ] if talent
                end
              else
                []
              end
            end.uniq { |blizzard_id, _| blizzard_id }.compact
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
            values = id_map.map do |blizzard_id, talent_id|
              a        = talent_attrs[blizzard_id]
              spell_id = a[:spell_id] ? a[:spell_id].to_i.to_s : "NULL"
              "(#{talent_id.to_i}, #{a[:node_id].to_i}, #{a[:display_row].to_i}, " \
                "#{a[:display_col].to_i}, #{a[:max_rank].to_i}, #{spell_id})"
            end.join(", ")

            ApplicationRecord.connection.execute(<<~SQL)
              UPDATE talents
              SET node_id = v.node_id, display_row = v.display_row,
                  display_col = v.display_col, max_rank = v.max_rank,
                  spell_id = v.spell_id, updated_at = NOW()
              FROM (VALUES #{values})
                AS v(id, node_id, display_row, display_col, max_rank, spell_id)
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

            TalentPrerequisite.delete_all
            # rubocop:disable Rails/SkipsModelValidations
            TalentPrerequisite.insert_all!(rows)
            # rubocop:enable Rails/SkipsModelValidations
          end

          # rubocop:disable Metrics/MethodLength
          def apply_spec_assignments(spec_assignments)
            return if spec_assignments.empty?

            all_blizzard_ids = spec_assignments.values.flat_map(&:to_a).uniq
            id_map = Talent
              .where(blizzard_id: all_blizzard_ids)
              .pluck(:blizzard_id, :id)
              .to_h

            now  = Time.current
            rows = spec_assignments.flat_map do |spec_id, blizzard_ids|
              blizzard_ids.filter_map do |blizzard_id|
                talent_id = id_map[blizzard_id]
                next unless talent_id

                { talent_id: talent_id, spec_id: spec_id, created_at: now, updated_at: now }
              end
            end

            return if rows.empty?

            # rubocop:disable Rails/SkipsModelValidations
            TalentSpecAssignment.insert_all(rows, unique_by: %i[talent_id spec_id])
            # rubocop:enable Rails/SkipsModelValidations
          end
          # rubocop:enable Metrics/MethodLength

          # Fetches /data/wow/talent/{id} for talents missing an icon or description,
          # storing spell_id, icon_url, and the max-rank description translation in one pass.
          def fetch_missing_media
            media_incomplete_scope.find_each { |talent| sync_talent_media(talent) }
          end

          def media_incomplete_scope
            Talent.where(
              "icon_url IS NULL OR id NOT IN (" \
                "SELECT translatable_id FROM translations " \
                "WHERE translatable_type = 'Talent' AND key = 'description' AND locale = ?" \
              ")",
              client.locale
            )
          end

          def sync_talent_media(talent)
            talent_data = fetch_talent_data(talent.blizzard_id)
            spell_id    = talent.spell_id || talent_data[:spell_id]
            return unless spell_id

            save_description(talent, talent_data[:description])
            sync_icon(talent, spell_id) if talent.icon_url.nil?
          rescue Blizzard::Client::NotFoundError
            # no entry in Blizzard's API — skip silently
          rescue Blizzard::Client::Error => e
            Rails.logger.warn("[SyncTreeService] Media fetch failed for talent #{talent.blizzard_id}: #{e.message}")
          end

          def sync_icon(talent, spell_id)
            url = fetch_spell_icon_url(spell_id)
            # rubocop:disable Rails/SkipsModelValidations
            Talent.where(id: talent.id).update_all(icon_url: url, spell_id: spell_id) if url
            # rubocop:enable Rails/SkipsModelValidations
          end

          # Fetches /data/wow/talent/{id} and returns { spell_id:, description: }.
          # description is the max-rank description (highest rank players invest in).
          def fetch_talent_data(blizzard_id)
            data  = client.get("/data/wow/talent/#{blizzard_id}", namespace: client.static_namespace)
            ranks = Array(data["rank_descriptions"])
            desc  = ranks.max_by { |r| r["rank"].to_i }&.dig("description")

            { spell_id: data.dig("spell", "id"), description: desc }
          end

          def save_description(talent, description)
            return unless description.present?

            talent.set_translation("description", client.locale, description, meta: { source: "blizzard" })
          end

          def fetch_spell_icon_url(spell_id)
            data = client.get(
              "/data/wow/media/spell/#{spell_id}",
              namespace: client.static_namespace
            )
            Array(data["assets"]).find { |a| a["key"] == "icon" }&.dig("value")
          end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
