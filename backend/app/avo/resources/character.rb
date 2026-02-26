class Avo::Resources::Character < Avo::BaseResource
  self.default_sort_column = :id
  self.default_sort_direction = :asc
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  self.profile_photo = {
    source: -> {
      if view.index?
        nil
      else
        record.avatar_url || DEFAULT_IMAGE
      end
    }
  }

  self.cover_photo = {
    size: :lg,
    source: -> {
      if view.index?
        nil
      else
        record.inset_url || DEFAULT_IMAGE
      end
    }
  }

  def actions
    action Avo::Actions::SyncCharacterAction
  end

  def fields
    field :id, as: :id
    field :blizzard_id, as: :number
    field :name, as: :text
    field :realm, as: :text
    field :region, as: :text

    field :faction, as: :select, enum: ::Character.factions
    field :is_private, as: :boolean

    field :race, as: :text
    field :class_slug, as: :text
    field :avatar_url, as: :text

    field :equipment_last_modified, as: :text
    field :equipment_fingerprint, as: :text

    field :inset_url, as: :text


    field :last_equipment_snapshot_at, as: :date_time
    field :main_raw_url, as: :text
    field :meta_synced_at, as: :date_time

    field :race_id, as: :number

    field :talent_loadout_code, as: :text
    field :talents_last_modified, as: :text
    field :unavailable_until, as: :date_time
    field :character_talents, as: :has_many
    field :character_items, as: :has_many
  end
end
