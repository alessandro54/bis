class Avo::Resources::CharacterTalent < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :character_id, as: :number
    field :rank, as: :number
    field :slot_number, as: :number
    field :talent_id, as: :number
    field :talent_type, as: :text
    field :character, as: :belongs_to
    field :talent, as: :belongs_to
  end
end
