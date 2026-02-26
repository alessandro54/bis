class Avo::Resources::PvpLeaderboardEntry < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :character_id, as: :number
    field :equipment_processed_at, as: :date_time
    field :hero_talent_tree_id, as: :number
    field :hero_talent_tree_name, as: :text
    field :item_level, as: :number
    field :losses, as: :number
    field :pvp_leaderboard_id, as: :number
    field :rank, as: :number
    field :rating, as: :number
    field :raw_equipment, as: :number
    field :raw_specialization, as: :number
    field :snapshot_at, as: :date_time
    field :spec_id, as: :number
    field :specialization_processed_at, as: :date_time
    field :tier_4p_active, as: :boolean
    field :tier_set_id, as: :number
    field :tier_set_name, as: :text
    field :tier_set_pieces, as: :number
    field :wins, as: :number
    field :pvp_leaderboard, as: :belongs_to
    field :character, as: :belongs_to
  end
end
