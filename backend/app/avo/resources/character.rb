class Avo::Resources::Character < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :avatar_url, as: :text
    field :blizzard_id, as: :number
    field :class_id, as: :number
    field :class_slug, as: :text
    field :equipment_last_modified, as: :text
    field :equipment_fingerprint, as: :text
    field :faction, as: :select, enum: ::Character.factions
    field :inset_url, as: :text
    field :is_private, as: :boolean
    field :last_equipment_snapshot_at, as: :date_time
    field :main_raw_url, as: :text
    field :meta_synced_at, as: :date_time
    field :name, as: :text
    field :race, as: :text
    field :race_id, as: :number
    field :realm, as: :text
    field :region, as: :text
    field :talent_loadout_code, as: :text
    field :talents_last_modified, as: :text
    field :unavailable_until, as: :date_time
    field :character_talents, as: :has_many
    field :character_items, as: :has_many
  end
end
