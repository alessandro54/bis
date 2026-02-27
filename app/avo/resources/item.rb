class Avo::Resources::Item < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :blizzard_id, as: :number
    field :blizzard_media_id, as: :number
    field :icon_url, as: :text
    field :inventory_type, as: :text
    field :item_class, as: :text
    field :item_subclass, as: :text
    field :meta_synced_at, as: :date_time
    field :quality, as: :text
    field :translations, as: :has_many
    field :character_items, as: :has_many
    field :characters, as: :has_many, through: :character_items
  end
end
