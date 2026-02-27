class Avo::Resources::Talent < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :blizzard_id, as: :number
    field :spell_id, as: :number
    field :talent_type, as: :text
    field :translations, as: :has_many
    field :character_talents, as: :has_many
  end
end
