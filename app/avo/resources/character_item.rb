class Avo::Resources::CharacterItem < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :bonus_list, as: :number
    field :character_id, as: :number
    field :context, as: :number
    field :crafting_stats, as: :text
    field :embellishment_spell_id, as: :number
    field :enchantment_id, as: :number
    field :enchantment_source_item_id, as: :number
    field :item_id, as: :number
    field :item_level, as: :number
    field :slot, as: :text
    field :sockets, as: :code
    field :character, as: :belongs_to
    field :item, as: :belongs_to
    field :enchantment, as: :belongs_to
    field :enchantment_source_item, as: :belongs_to
  end
end
