class Avo::Resources::PvpLeaderboard < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: q, m: "or").result(distinct: false) }
  # }

  def fields
    field "Season", as: :number do
      record.pvp_season&.display_name rescue ""
    end

    field :region, as: :text
    field :bracket, as: :text
    field :last_synced_at, as: :date_time
    field :entries, as: :has_many
  end
end
