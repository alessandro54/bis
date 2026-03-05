class Character::TalentTreePrinter
  CELL_W = 14  # chars per cell including brackets

  COLORS = {
    class: "\e[33m",
    spec:  "\e[36m",
    hero:  "\e[35m"
  }.freeze

  def self.call(character, spec_id: nil)
    new(character).call(spec_id: spec_id)
  end

  def initialize(character)
    @character = character
  end

  def call(spec_id: nil)
    char_data = fetch_char_spec_data
    return puts "#{bold}No specialization data found.#{reset}" unless char_data

    specs = char_data["specializations"] || []
    specs = specs.select { |s| s["specialization"]["id"] == spec_id } if spec_id

    specs.each do |spec_data|
      spec    = spec_data["specialization"]
      loadout = spec_data["loadouts"]&.find { |l| l["is_active"] }

      puts "\n#{COLORS[:spec]}#{bold}#{"═" * 72}#{reset}"
      puts "#{COLORS[:spec]}#{bold}  #{spec["name"].upcase} (spec #{spec["id"]})#{reset}"
      puts "#{COLORS[:spec]}#{bold}#{"═" * 72}#{reset}"

      unless loadout
        puts "  #{dim}(no active loadout)#{reset}"
        next
      end

      puts "  #{dim}#{loadout["talent_loadout_code"]}#{reset}\n"

      tree_id   = extract_tree_id(loadout["selected_class_talent_tree"])
      game_tree = tree_id ? fetch_game_tree(tree_id, spec["id"]) : nil

      unless game_tree
        puts "  #{dim}(could not fetch game tree data)#{reset}"
        next
      end

      # selected[node_id] = rank
      selected_class = extract_selected(loadout["selected_class_talents"])
      selected_spec  = extract_selected(loadout["selected_spec_talents"])
      selected_hero  = extract_selected(loadout["selected_hero_talents"])

      # blizzard_ids of chosen talents — resolves which side of choice nodes
      chosen_blizzard_ids = @character.character_talents
        .where(spec_id: spec["id"])
        .joins(:talent)
        .pluck("talents.blizzard_id")
        .to_set

      section "CLASS TALENTS", :class
      render_grid(game_tree["class_talent_nodes"],  selected_class, chosen_blizzard_ids, :class)

      # Blizzard includes all hero tree nodes inside spec_talent_nodes — exclude them
      hero_node_ids = (game_tree["hero_talent_trees"] || [])
        .flat_map { |h| h["hero_talent_nodes"] || [] }
        .map { |n| n["id"] }
        .to_set
      spec_nodes = game_tree["spec_talent_nodes"].reject { |n| hero_node_ids.include?(n["id"]) }

      section "SPEC TALENTS", :spec
      render_grid(spec_nodes, selected_spec, chosen_blizzard_ids, :spec)

      hero_id   = loadout.dig("selected_hero_talent_tree", "id")
      hero_data = game_tree["hero_talent_trees"]&.find { |h| h["id"] == hero_id }
      if hero_data&.dig("hero_talent_nodes")&.any?
        section "HERO TALENTS — #{hero_data["name"]}", :hero
        render_grid(hero_data["hero_talent_nodes"], selected_hero, chosen_blizzard_ids, :hero)
      end
    end

    nil
  end

  private

    def section(label, key)
      c = COLORS[key]
      puts "\n  #{c}#{bold}#{label}#{reset}"
      puts "  #{dim}#{"─" * 68}#{reset}"
    end

    def render_grid(nodes, selected, chosen_blizzard_ids, color_key)
      return puts "  #{dim}(empty)#{reset}" if nodes.nil? || nodes.empty?

      color = COLORS[color_key]

      all_rows = nodes.map { |n| n["display_row"] }.uniq.sort
      all_cols = nodes.map { |n| n["display_col"] }.uniq.sort

      col_idx = all_cols.each_with_index.to_h

      # group by row
      by_row = nodes.group_by { |n| n["display_row"] }

      all_rows.each do |row_num|
        row_nodes = by_row[row_num] || []
        cells = Array.new(all_cols.size, nil)
        row_nodes.each { |n| cells[col_idx[n["display_col"]]] = n }

        # skip fully-empty rows that have no node at all
        next if cells.all?(&:nil?)

        line = cells.map do |node|
          node ? render_cell(node, selected, chosen_blizzard_ids, color) : " " * (CELL_W + 1)
        end.join

        puts "  " + line.rstrip
      end
    end

    def render_cell(node, selected, chosen_blizzard_ids, color)
      rank     = selected[node["id"]]  # nil if not selected
      is_sel   = !rank.nil?

      name, max_rank = node_name_and_max(node, chosen_blizzard_ids)
      short    = name.length > (CELL_W - 4) ? name[0, CELL_W - 5] + "…" : name
      rank_str = (max_rank || 1) > 1 ? " #{rank || 0}/#{max_rank}" : ""
      content  = (short + rank_str).ljust(CELL_W - 2)

      if is_sel
        "#{color}[#{content}]#{reset} "
      else
        "#{dim}(#{content})#{reset} "
      end
    end

    # Returns [display_name, max_rank]
    def node_name_and_max(node, chosen_blizzard_ids)
      ranks = node["ranks"] || []
      max_rank = ranks.size
      first = ranks.first || {}

      if (choices = first["choice_of_tooltips"])
        names = choices.map { |c| c.dig("talent", "name") || "?" }
        chosen = choices.find { |c| chosen_blizzard_ids.include?(c.dig("talent", "id")) }
        name = chosen ? "> #{chosen.dig("talent", "name")}" : names.join("/")
        [ name, 1 ]
      elsif (tooltip = first["tooltip"])
        [ tooltip.dig("talent", "name") || "?", max_rank ]
      else
        [ "???", max_rank ]
      end
    end

    def extract_selected(arr)
      (arr || []).each_with_object({}) { |t, h| h[t["id"]] = t["rank"] }
    end

    def extract_tree_id(ref)
      href = ref&.dig("key", "href") || ""
      href.match(%r{/talent-tree/(\d+)})&.captures&.first&.to_i
    end

    def fetch_char_spec_data
      Blizzard::Api::Profile::CharacterSpecializationSummary.fetch(
        region: @character.region,
        realm:  @character.realm,
        name:   @character.name,
        locale: "en_US"
      )
    rescue => e
      Rails.logger.error("[TalentTreePrinter] #{e.message}")
      nil
    end

    def fetch_game_tree(tree_id, spec_id)
      client = Blizzard.client(region: @character.region, locale: "en_US")
      client.get(
        "/data/wow/talent-tree/#{tree_id}/playable-specialization/#{spec_id}",
        namespace: client.static_namespace,
        params: { locale: "en_US" }
      )
    rescue => e
      Rails.logger.error("[TalentTreePrinter] #{e.message}")
      nil
    end

    def reset = "\e[0m"
    def bold  = "\e[1m"
    def dim   = "\e[2m"
end
