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

    primary_spec_id = pvp_entries.max_by(&:rating)&.spec_id

    render json: {
      name:            character.name,
      realm:           character.realm,
      region:          character.region.upcase,
      class_slug:      character.class_slug,
      race:            character.race,
      faction:         character.faction,
      avatar_url:      character.avatar_url,
      inset_url:       character.inset_url,
      primary_spec_id: primary_spec_id,
      stat_pcts:       character.stat_pcts || {},
      pvp_entries:     pvp_entries.map { |e|
        {
          bracket: e.bracket,
          region:  e.region.upcase,
          rating:  e.rating,
          wins:    e.wins,
          losses:  e.losses,
          rank:    e.rank,
          spec_id: e.spec_id
        }
      },
      equipment:       primary_spec_id ? build_equipment(character, primary_spec_id) : [],
      talents:         primary_spec_id ? build_talents(character, primary_spec_id) : []
    }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  private

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def build_equipment(character, spec_id)
      items = character.character_items.where(spec_id: spec_id).includes(:item)
      return [] if items.empty?

      item_names = Translation
        .where(translatable_type: "Item", translatable_id: items.map(&:item_id), key: "name", locale: "en_US")
        .pluck(:translatable_id, :value).to_h

      enchant_ids = items.filter_map(&:enchantment_id)
      enchant_names = enchant_ids.any? ? Translation
        .where(translatable_type: "Enchantment", translatable_id: enchant_ids, key: "name", locale: "en_US")
        .pluck(:translatable_id, :value).to_h : {}

      items.map do |ci|
        {
          slot:        ci.slot,
          item_level:  ci.item_level,
          quality:     ci.item&.quality,
          blizzard_id: ci.item&.blizzard_id,
          name:        item_names[ci.item_id],
          icon_url:    ci.item&.icon_url,
          enchant:     enchant_names[ci.enchantment_id],
          sockets:     Array(ci.sockets).filter_map { |s| s["display_string"].presence }
        }
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def build_talents(character, spec_id)
      all_talent_ids = TalentSpecAssignment.where(spec_id: spec_id).pluck(:talent_id)
      return [] if all_talent_ids.empty?

      selected = CharacterTalent
        .where(character_id: character.id, spec_id: spec_id)
        .pluck(:talent_id, :talent_type, :rank, :slot_number)
        .to_h { |(tid, ttype, rank, slot)| [ tid, { type: ttype, rank: rank, slot: slot } ] }

      # PvP talents selected by the character but outside the spec tree
      pvp_extra_ids = selected.keys.select { |tid| selected.dig(tid, :type) == "pvp" } - all_talent_ids
      all_ids       = all_talent_ids + pvp_extra_ids

      all_talents = Talent.includes(:translations).where(id: all_ids)

      node_ids = all_talents.filter_map(&:node_id).uniq
      prereqs  = node_ids.any? ? TalentPrerequisite
        .where(node_id: node_ids)
        .group_by(&:node_id)
        .transform_values { |ps| ps.map(&:prerequisite_node_id) } : {}

      default_pts = TalentSpecAssignment
        .where(talent_id: all_ids, spec_id: spec_id)
        .pluck(:talent_id, :default_points).to_h

      all_talents.map do |t|
        ct = selected[t.id]
        {
          id:             nil,
          talent:         {
            id:                    t.id,
            blizzard_id:           t.blizzard_id,
            name:                  t.t("name", locale: "en_US"),
            description:           t.t("description", locale: "en_US"),
            talent_type:           t.talent_type,
            spell_id:              t.spell_id,
            node_id:               t.node_id,
            display_row:           t.display_row,
            display_col:           t.display_col,
            max_rank:              t.max_rank,
            icon_url:              t.icon_url,
            default_points:        default_pts[t.id] || 0,
            prerequisite_node_ids: prereqs[t.node_id] || []
          },
          usage_count:    ct ? (ct[:rank] || 1) : 0,
          usage_pct:      ct ? 1.0 : 0.0,
          in_top_build:   ct.present?,
          top_build_rank: 0,
          tier:           ct ? "bis" : "common",
          snapshot_at:    nil
        }
      end
    end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
