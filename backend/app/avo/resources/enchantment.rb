class Avo::Resources::Enchantment < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :blizzard_id, as: :number
    field :translations, as: :has_many
    field :character_items, as: :has_many
  end
end
