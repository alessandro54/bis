class Avo::Resources::PvpSeason < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :blizzard_id, as: :number
    field :display_name, as: :text
    field :end_time, as: :date_time
    field :is_current, as: :boolean
    field :start_time, as: :date_time
    field :pvp_leaderboards, as: :has_many
  end
end
