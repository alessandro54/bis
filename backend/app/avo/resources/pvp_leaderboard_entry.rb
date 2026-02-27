class Avo::Resources::PvpLeaderboardEntry < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }
  #
  self.default_sort_column = :rank
  self.default_sort_direction = :asc

  def filters
    filter Avo::Filters::PvpLeaderboardFilter
    filter Avo::Filters::ItemLevelFilter
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def fields
    field :rank, as: :number
    field :rating, as: :number

    field "bracket", as: :text do
      bracket_name = record.pvp_leaderboard.bracket

      bracket_name.include?("shuffle") ? "shuffle" : bracket_name
    end

    field "spec", as: :text do
      Wow::Specs.slug_for(record.spec_id) if record.spec_id
    end

    field "class", as: :text do
      record.character.class_slug
    end

    field :wins, as: :number
    field :losses, as: :number

    field "win_percentage", as: :text do
      "#{(record.wins.to_f / (record.wins + record.losses) * 100).round(2)} %" rescue ""
    end

    field :character, as: :belongs_to

    field "equipment_last_modified", as: :text do
      record.character.equipment_last_modified&.in_time_zone("America/Lima")&.strftime("%B %d, %Y %I:%M %p")
    end

    field :equipment_processed_at, as: :date_time
    field :specialization_processed_at, as: :date_time

    field :hero_talent_tree_name, as: :text
    field :item_level, as: :number
    field :pvp_leaderboard_id, as: :number

    field :snapshot_at, as: :date_time
    field :spec_id, as: :number

    field :tier_4p_active, as: :boolean
    field :tier_set_id, as: :number
    field :tier_set_name, as: :text
    field :tier_set_pieces, as: :number
    field :pvp_leaderboard, as: :belongs_to
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
end
