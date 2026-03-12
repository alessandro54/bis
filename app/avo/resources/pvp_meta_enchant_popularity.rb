class Avo::Resources::PvpMetaEnchantPopularity < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def actions
    action Avo::Actions::DeleteSelectedAction
  end

  def fields
    field :id, as: :id
    field :bracket, as: :text
    field :enchantment_id, as: :number
    field :pvp_season_id, as: :number
    field :slot, as: :text
    field :snapshot_at, as: :date_time
    field :spec_id, as: :number
    field :usage_count, as: :number
    field :usage_pct, as: :number
    field :pvp_season, as: :belongs_to
    field :enchantment, as: :belongs_to
  end
end
